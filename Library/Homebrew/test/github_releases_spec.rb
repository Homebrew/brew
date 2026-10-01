# typed: strict
# frozen_string_literal: true

require "github_releases"

RSpec.describe GitHubReleases do
  describe "#upload_bottles" do
    it "reports progress when uploading many bottles" do
      events = []
      bottles_hash = %w[foo bar baz].to_h do |formula_name|
        [formula_name, {
          "bottle" => {
            "root_url" => "https://github.com/homebrew/homebrew-core/releases/download/test",
            "tags"     => {
              "arm64"  => {
                "filename"       => "#{formula_name}-arm64.bottle.tar.gz",
                "local_filename" => "#{formula_name}-arm64.local.bottle.tar.gz",
              },
              "x86_64" => {
                "filename"       => "#{formula_name}-x86_64.bottle.tar.gz",
                "local_filename" => "#{formula_name}-x86_64.local.bottle.tar.gz",
              },
            },
          },
        }]
      end
      allow(GitHub).to receive(:get_release).and_return({ "id" => 123 })
      allow(GitHub).to receive(:upload_release_asset) do |_, _, _, local_file:, remote_file:|
        events << "Uploaded #{remote_file} from #{local_file}"
      end
      github_releases = described_class.new
      allow(github_releases).to receive(:ohai) { |message| events << message }

      github_releases.upload_bottles(bottles_hash)

      expect(events).to eq([
        "Uploaded foo-arm64.bottle.tar.gz from foo-arm64.local.bottle.tar.gz",
        "Uploaded foo-x86_64.bottle.tar.gz from foo-x86_64.local.bottle.tar.gz",
        "Upload progress: 1 formula(e) uploaded, 2 remaining",
        "Uploaded bar-arm64.bottle.tar.gz from bar-arm64.local.bottle.tar.gz",
        "Uploaded bar-x86_64.bottle.tar.gz from bar-x86_64.local.bottle.tar.gz",
        "Upload progress: 2 formula(e) uploaded, 1 remaining",
        "Uploaded baz-arm64.bottle.tar.gz from baz-arm64.local.bottle.tar.gz",
        "Uploaded baz-x86_64.bottle.tar.gz from baz-x86_64.local.bottle.tar.gz",
        "Upload progress: 3 formula(e) uploaded, 0 remaining",
      ])
    end

    it "does not report progress when uploading fewer than three bottles" do
      events = []
      bottles_hash = %w[foo bar].to_h do |formula_name|
        [formula_name, {
          "bottle" => {
            "root_url" => "https://github.com/homebrew/homebrew-core/releases/download/test",
            "tags"     => {
              "arm64" => {
                "filename"       => "#{formula_name}-arm64.bottle.tar.gz",
                "local_filename" => "#{formula_name}-arm64.local.bottle.tar.gz",
              },
            },
          },
        }]
      end
      allow(GitHub).to receive(:get_release).and_return({ "id" => 123 })
      allow(GitHub).to receive(:upload_release_asset) do |_, _, _, local_file:, remote_file:|
        events << "Uploaded #{remote_file} from #{local_file}"
      end
      github_releases = described_class.new
      allow(github_releases).to receive(:ohai) { |message| events << message }

      github_releases.upload_bottles(bottles_hash)

      expect(events).to eq([
        "Uploaded foo-arm64.bottle.tar.gz from foo-arm64.local.bottle.tar.gz",
        "Uploaded bar-arm64.bottle.tar.gz from bar-arm64.local.bottle.tar.gz",
      ])
    end
  end
end
