# typed: true
# frozen_string_literal: true

require "github_packages"

RSpec.describe GitHubPackages do
  describe ".downloads" do
    before do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 23, 12))
      allow(Utils::Curl).to receive(:curl_output).and_return(
        instance_double(SystemCommand::Result, success?: true, stdout: <<~HTML),
          <span>Total downloads</span><h3 title="22776486">22.8M</h3>
          <div aria-label="Downloads for the last 30 days"><svg>
            <rect data-merge-count="1234" data-date="2026-10-23"></rect>
            <rect data-date="2026-10-22" data-merge-count="2345"></rect>
          </svg></div>
        HTML
      )
    end

    it "reads exact package totals instead of rounded totals or recent tags" do
      expect(described_class.downloads("wget")&.serialize).to include(
        "all_time" => 22_776_486, "last_30_days" => 3579,
        "start_date" => "2026-10-22", "end_date" => "2026-10-23",
        "fetched_at" => "2026-10-23T12:00:00Z"
      )
    end

    it "reuses a successful snapshot on the same UTC day" do
      described_class.downloads("wget")
      expect(Utils::Curl).not_to receive(:curl_output)

      described_class.downloads("wget")
    end

    it "refreshes a snapshot on the next UTC day" do
      described_class.downloads("wget")
      allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24))
      expect(Utils::Curl).to receive(:curl_output).once

      described_class.downloads("wget")
    end

    it "does not interpret missing chart data as zero downloads" do
      allow(Utils::Curl).to receive(:curl_output).and_return(
        instance_double(SystemCommand::Result, success?: true, stdout: '<h3 title="100">100</h3>'),
      )

      expect(described_class.downloads("wget")).to be_nil
    end
  end

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
      allow(Utils::Executable).to receive(:ensure!).and_return(Pathname("skopeo"))
      allow(github_packages).to receive(:build_image) do |_, _, _, formula_full_name, *_args, **_options|
        GitHubPackages::Image.new(root: Pathname(formula_full_name), uri: formula_full_name, package_url: "",
                                  index_sha256: "")
      end
      allow(github_packages).to receive(:preupload_check).and_return(["foo", nil])
      allow(github_packages).to receive(:upload_image) { |_, _, _, image, **_options|
        events << "Uploaded #{image.uri}"
      }
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
      allow(Utils::Executable).to receive(:ensure!).and_return(Pathname("skopeo"))
      allow(github_packages).to receive(:build_image) do |_, _, _, formula_full_name, *_args, **_options|
        GitHubPackages::Image.new(root: Pathname(formula_full_name), uri: formula_full_name, package_url: "",
                                  index_sha256: "")
      end
      allow(github_packages).to receive(:preupload_check).and_return(["foo", nil])
      allow(github_packages).to receive(:upload_image) { |_, _, _, image, **_options|
        events << "Uploaded #{image.uri}"
      }
      allow(github_packages).to receive(:ohai) { |message| events << message }

      github_packages.upload_bottles(bottles_hash, keep_old: false, dry_run: false, warn_on_error: false)

      expect(events).to eq([
        "Uploaded foo",
        "Uploaded bar",
      ])
    end

    it "gives each image index digest to the block before uploading anything" do
      github_packages = described_class.new
      events = []

      allow(Homebrew::EnvConfig).to receive_messages(
        github_packages_user:  "brewtest",
        github_packages_token: "ghp_test",
      )
      allow(github_packages).to receive(:load_schemas!)
      allow(Utils::Executable).to receive(:ensure!).and_return(Pathname("skopeo"))
      allow(github_packages).to receive_messages(
        build_image:     GitHubPackages::Image.new(root: Pathname("foo"), uri: "foo", package_url: "",
                                                   index_sha256: "index-sha256"),
        preupload_check: ["foo", nil],
      )
      allow(github_packages).to receive(:upload_image) { events << "Uploaded" }

      github_packages.upload_bottles({ "foo" => {} }, keep_old: false, dry_run: false,
                                     warn_on_error: false) { |manifest_sha256s| events << manifest_sha256s }

      expect(events).to eq([{ "foo" => "index-sha256" }, "Uploaded"])
    end

    it "does not replace an image index that changed after `--keep-old` built on it" do
      github_packages = described_class.new

      allow(Homebrew::EnvConfig).to receive_messages(
        github_packages_user:  "brewtest",
        github_packages_token: "ghp_test",
      )
      allow(github_packages).to receive(:load_schemas!)
      allow(Utils::Executable).to receive(:ensure!).and_return(Pathname("skopeo"))
      allow(github_packages).to receive_messages(
        build_image:     GitHubPackages::Image.new(root: Pathname("foo"), uri: "foo", package_url: "",
                                                   index_sha256: "", base_index_sha256: "built-on"),
        preupload_check: ["foo", "changed"],
      )
      expect(github_packages).not_to receive(:upload_image)

      expect { github_packages.upload_bottles({ "foo" => {} }, keep_old: true, dry_run: false, warn_on_error: false) }
        .to raise_error(SystemExit).and output(/foo changed/).to_stderr
    end

    it "fails instead of skipping an image it cannot upload once the block pinning it is committed" do
      github_packages = described_class.new

      allow(Homebrew::EnvConfig).to receive_messages(github_packages_user:  "brewtest",
                                                     github_packages_token: "ghp_test")
      allow(Utils::Executable).to receive(:ensure!).and_return(Pathname("skopeo"))
      allow(github_packages).to receive_messages(
        load_schemas!: nil,
        upload_image:  nil,
        build_image:   GitHubPackages::Image.new(root: Pathname("foo"), uri: "foo", package_url: "",
                                                 index_sha256: ""),
      )
      expect(github_packages).to receive(:preupload_check)
        .with(any_args, hash_including(warn_on_error: false))
        .and_return(["foo", nil])

      github_packages.upload_bottles({ "foo" => {} }, keep_old: false, dry_run: false, warn_on_error: true)
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

  describe "#upload_image" do
    it "has `skopeo` fail instead of uploading another image index than the one a bottle block pins" do
      image = GitHubPackages::Image.new(root: Pathname("foo"), uri: "foo", package_url: "", index_sha256: "")

      expect { described_class.new.upload_image("user", "token", Pathname("skopeo"), image, dry_run: true) }
        .to output(/ --preserve-digests /).to_stdout
    end
  end

  describe "#build_image" do
    it "builds formulae that share a name in different taps in their own directories" do
      mktmpdir.cd do
        github_packages = Class.new(GitHubPackages) do
          private

          def validate_schema!(_schema_uri, _json); end
        end.new
        allow(github_packages).to receive(:puts)

        expect(github_packages.build_image(
          "brewtest", "ghp_test", Pathname("skopeo"), "user/tap/testball",
          { "formula" => { "name" => "testball", "pkg_version" => "1.0" },
            "bottle"  => { "root_url" => "https://ghcr.io/v2/user/tap", "tags" => {} } },
          keep_old: false, dry_run: true, warn_on_error: false
        )&.root).to eq(Pathname("user/tap/testball--1.0"))
      end
    end

    it "omits platform metadata from image index descriptors for all bottles" do
      mktmpdir.cd do
        bottle = Pathname("testball--1.0.all.bottle.tar.gz")
        Zlib::GzipWriter.open(bottle) { |gz| gz.write("test") }

        github_packages = Class.new(GitHubPackages) do
          private

          def validate_schema!(_schema_uri, _json); end
        end.new

        image = T.let(nil, T.nilable(GitHubPackages::Image))
        expect do
          image = github_packages.build_image("brewtest", "ghp_test", Pathname("skopeo"), "testball",
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
        # A bottle block pins this digest, so it has to be that of the index uploaded.
        expect(image&.index_sha256).to eq(image_index_sha256)
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
