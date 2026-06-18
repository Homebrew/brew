# typed: true
# frozen_string_literal: true

require "github_packages"

RSpec.describe GitHubPackages do
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
          github_packages.send(:upload_bottle, "brewtest", "ghp_test", Pathname("skopeo"), "testball",
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
                                       "installed_size" => 100,
                                     },
                                     "arm64_sonoma" => {
                                       "local_filename" => bottle.to_s,
                                       "tab"            => {
                                         "arch"     => "arm64",
                                         "built_on" => {
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
        expect(manifests_by_tag.fetch("1.0.arm64_sonoma"))
          .to include("platform" => include("architecture" => "arm64", "os" => "darwin"))
        expect(JSON.parse(manifests_by_tag.fetch("1.0.arm64_sonoma").fetch("annotations").fetch("sh.brew.tab")))
          .to include("arch" => "arm64", "built_on" => include("os" => "Macintosh"))
      end
    end
  end
end
