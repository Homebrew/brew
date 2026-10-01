# typed: true
# frozen_string_literal: true

require "github_packages"

RSpec.describe GitHubPackages do
  describe "#upload_bottles" do
    it "reports progress when uploading many bottles" do
      github_packages = described_class.new
      events = []
      bottles_hash = {
        "foo" => {},
        "bar" => {},
        "baz" => {},
      }

      allow(Homebrew::EnvConfig).to receive_messages(
        github_packages_user:  "brewtest",
        github_packages_token: "ghp_test",
      )
      allow(github_packages).to receive(:load_schemas!)
      allow(github_packages).to receive(:preupload_check)
      allow(Utils::Executable).to receive(:ensure!).and_return(Pathname("skopeo"))
      allow(github_packages).to receive(:upload_bottle) do |_, _, _, formula_full_name, *_args, **_options|
        events << "Uploaded #{formula_full_name}"
      end
      allow(github_packages).to receive(:ohai) { |message| events << message }

      github_packages.upload_bottles(bottles_hash, keep_old: false, dry_run: false, warn_on_error: false)

      expect(events).to eq([
        "Uploaded foo",
        "Upload progress: 1 formula(e) uploaded, 2 remaining",
        "Uploaded bar",
        "Upload progress: 2 formula(e) uploaded, 1 remaining",
        "Uploaded baz",
        "Upload progress: 3 formula(e) uploaded, 0 remaining",
      ])
    end

    it "does not report progress when uploading fewer than three bottles" do
      github_packages = described_class.new
      events = []
      bottles_hash = {
        "foo" => {},
        "bar" => {},
      }

      allow(Homebrew::EnvConfig).to receive_messages(
        github_packages_user:  "brewtest",
        github_packages_token: "ghp_test",
      )
      allow(github_packages).to receive(:load_schemas!)
      allow(github_packages).to receive(:preupload_check)
      allow(Utils::Executable).to receive(:ensure!).and_return(Pathname("skopeo"))
      allow(github_packages).to receive(:upload_bottle) do |_, _, _, formula_full_name, *_args, **_options|
        events << "Uploaded #{formula_full_name}"
      end
      allow(github_packages).to receive(:ohai) { |message| events << message }

      github_packages.upload_bottles(bottles_hash, keep_old: false, dry_run: false, warn_on_error: false)

      expect(events).to eq([
        "Uploaded foo",
        "Uploaded bar",
      ])
    end

    it "includes skipped bottles in progress" do
      github_packages = described_class.new
      bottles_hash = {
        "foo" => {},
        "bar" => {},
        "baz" => {},
      }

      allow(Homebrew::EnvConfig).to receive_messages(
        github_packages_user:  "brewtest",
        github_packages_token: "ghp_test",
      )
      allow(Utils::Executable).to receive(:ensure!).and_return(Pathname("skopeo"))
      allow(github_packages).to receive(:load_schemas!)
      allow(github_packages).to receive(:preupload_check)

      expect do
        github_packages.upload_bottles(bottles_hash, keep_old: false, dry_run: false, warn_on_error: true)
      end.to output(<<~EOS).to_stdout
        ==> Upload progress: 1 formula(e) uploaded, 2 remaining
        ==> Upload progress: 2 formula(e) uploaded, 1 remaining
        ==> Upload progress: 3 formula(e) uploaded, 0 remaining
      EOS
    end
  end

  describe "#upload_bottle" do
    it "omits platform metadata from image index descriptors for all bottles" do
      mktmpdir.cd do
        bottle = Pathname("testball--1.0.all.bottle.tar.gz")
        Zlib::GzipWriter.open(bottle) { |gz| gz.write("test") }

        github_packages = Class.new(GitHubPackages) do
          private

          def validate_schema!(_schema_uri, _json); end
        end.new

        expect do
          github_packages.upload_bottle("brewtest", "ghp_test", Pathname("skopeo"), "testball",
                                        {
                                          "formula" => {
                                            "name"             => "testball",
                                            "pkg_version"      => "1.0",
                                            "tap_git_path"     => "Formula/t/testball.rb",
                                            "tap_git_revision" => "abcdef",
                                            "desc"             => "Test formula",
                                            "license"          => "MIT",
                                            "homepage"         => "https://brew.sh/testball",
                                          },
                                          "bottle"  => {
                                            "root_url" => "https://ghcr.io/v2/homebrew/core",
                                            "rebuild"  => 0,
                                            "date"     => "2026-05-10T00:00:00Z",
                                            "tags"     => {
                                              "all"          => {
                                                "local_filename" => bottle.to_s,
                                                "tab"            => {
                                                  "arch"     => "arm64",
                                                  "built_on" => {
                                                    "os"         => "Macintosh",
                                                    "os_version" => "macOS 15",
                                                  },
                                                },
                                                "sbom"           => {
                                                  "documentDescribes" => ["SPDXRef-Compiler"],
                                                  "packages"          => [{ "SPDXID" => "SPDXRef-Compiler" }],
                                                  "relationships"     => [],
                                                },
                                                "installed_size" => 100,
                                              },
                                              "arm64_sonoma" => {
                                                "local_filename" => bottle.to_s,
                                                "tab"            => {
                                                  "arch"                    => "arm64",
                                                  "built_prefix"            => "/custom/prefix",
                                                  "linkage_files"           => ["bin/foo"],
                                                  "binary_relocation_files" => ["libexec/foo"],
                                                  "built_on"                => {
                                                    "os"         => "Macintosh",
                                                    "os_version" => "macOS 14",
                                                  },
                                                },
                                                "installed_size" => 100,
                                              },
                                            },
                                          },
                                        },
                                        keep_old: false, dry_run: true, warn_on_error: false)
        end.to output.to_stdout

        index_json = JSON.parse(Pathname("testball--1.0/index.json").read)
        image_index_sha256 = index_json.fetch("manifests").first.fetch("digest").delete_prefix("sha256:")
        image_index = JSON.parse((Pathname("testball--1.0/blobs/sha256")/image_index_sha256).read)
        manifests_by_tag = image_index.fetch("manifests").to_h do |manifest|
          [manifest.fetch("annotations").fetch("org.opencontainers.image.ref.name"), manifest]
        end

        expect(manifests_by_tag.fetch("1.0.all")).not_to have_key("platform")
        expect(JSON.parse(manifests_by_tag.fetch("1.0.all").fetch("annotations").fetch("sh.brew.tab")))
          .not_to include("arch", "built_on")
        all_annotations = manifests_by_tag.fetch("1.0.all").fetch("annotations")
        all_supplement = JSON.parse(all_annotations.fetch("sh.brew.sbom.supplement"))
        all_package_ids = all_supplement.fetch("packages").map { |package| package.fetch("SPDXID") }
        expect(all_package_ids).to include("SPDXRef-Compiler", "SPDXRef-Bottle-testball")
        expect(all_supplement.fetch("documentDescribes")).to include("SPDXRef-Bottle-testball")
        expect(all_supplement.fetch("packages").find do |package|
          package.fetch("SPDXID") == "SPDXRef-Bottle-testball"
        end.fetch("checksums")).to eq([
          {
            "algorithm"     => "SHA256",
            "checksumValue" => all_annotations.fetch("sh.brew.bottle.digest"),
          },
        ])
        expect(manifests_by_tag.fetch("1.0.arm64_sonoma"))
          .to include("platform" => include("architecture" => "arm64", "os" => "darwin"))
        expect(JSON.parse(manifests_by_tag.fetch("1.0.arm64_sonoma").fetch("annotations").fetch("sh.brew.tab")))
          .to include(
            "arch"                    => "arm64",
            "built_prefix"            => "/custom/prefix",
            "linkage_files"           => ["bin/foo"],
            "binary_relocation_files" => ["libexec/foo"],
            "built_on"                => include("os" => "Macintosh"),
          )
      end
    end
  end
end
