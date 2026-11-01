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
      expect(GitHub).not_to receive(:create_or_update_release)
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

    it "uploads all formula bottles before publishing a shared release" do
      events = []
      bottles_hash = {
        "foo" => "https://github.com/homebrew/homebrew-core/releases/download/test",
        "bar" => "https://github.com/Homebrew/Homebrew-Core/releases/download/test",
      }.to_h do |formula_name, root_url|
        [formula_name, {
          "bottle" => {
            "root_url" => root_url,
            "tags"     => {
              "arm64" => {
                "filename"       => "#{formula_name}-arm64.bottle.tar.gz",
                "local_filename" => "#{formula_name}-arm64.local.bottle.tar.gz",
              },
            },
          },
        }]
      end
      allow(GitHub).to receive(:get_release).and_raise(GitHub::API::HTTPNotFoundError.new("not found"))
      allow(GitHub).to receive(:create_or_update_release) do |user, repo, tag, **kwargs|
        events << [user, repo, tag, kwargs]
        { "id" => 123 }
      end
      allow(GitHub).to receive(:upload_release_asset) do |_, _, _, local_file:, remote_file:|
        events << "Uploaded #{remote_file} from #{local_file}"
      end

      described_class.new.upload_bottles(bottles_hash)

      expect(events).to eq([
        ["homebrew", "homebrew-core", "test", { draft: true }],
        "Uploaded foo-arm64.bottle.tar.gz from foo-arm64.local.bottle.tar.gz",
        "Uploaded bar-arm64.bottle.tar.gz from bar-arm64.local.bottle.tar.gz",
        ["homebrew", "homebrew-core", "test", { id: 123, draft: false }],
      ])
    end

    it "reuses a leftover draft release when creating a new release fails" do
      events = []
      bottles_hash = {
        "foo" => {
          "bottle" => {
            "root_url" => "https://github.com/homebrew/homebrew-core/releases/download/test",
            "tags"     => {
              "arm64" => {
                "filename"       => "foo-arm64.bottle.tar.gz",
                "local_filename" => "foo-arm64.local.bottle.tar.gz",
              },
            },
          },
        },
      }
      draft_release = { "id" => 456, "draft" => true }
      allow(GitHub).to receive(:get_release).and_raise(GitHub::API::HTTPNotFoundError.new("not found"))
      allow(GitHub).to receive(:create_or_update_release)
        .with("homebrew", "homebrew-core", "test", draft: true)
        .and_raise(GitHub::API::Error.new("tag_name already exists"))
      allow(GitHub).to receive(:create_or_update_release)
        .with("homebrew", "homebrew-core", "test", id: 456, draft: false)
        .and_return(draft_release)
      allow(GitHub).to receive(:get_draft_release).and_return(draft_release)
      allow(GitHub).to receive(:upload_release_asset) do |_, _, release_id, local_file:, remote_file:|
        events << "Uploaded #{remote_file} from #{local_file} to release #{release_id}"
      end
      github_releases = described_class.new
      allow(github_releases).to receive(:ohai) { |message| events << message }

      github_releases.upload_bottles(bottles_hash)

      expect(events).to eq(["Uploaded foo-arm64.bottle.tar.gz from foo-arm64.local.bottle.tar.gz " \
                            "to release 456"])
    end

    it "keeps a shared release in draft when a later formula upload fails" do
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
      allow(GitHub).to receive(:get_release).and_raise(GitHub::API::HTTPNotFoundError.new("not found"))
      allow(GitHub).to receive(:create_or_update_release)
        .with("homebrew", "homebrew-core", "test", draft: true)
        .and_return({ "id" => 123 })
      allow(GitHub).to receive(:upload_release_asset) do |_, _, _, remote_file:, **|
        raise GitHub::API::Error, "upload failed" if remote_file == "bar-arm64.bottle.tar.gz"
      end

      expect { described_class.new.upload_bottles(bottles_hash) }.to raise_error(GitHub::API::Error, "upload failed")
    end

    it "keeps releases with different repositories or tags separate" do
      events = []
      bottles_hash = {
        "foo" => "https://github.com/homebrew/homebrew-core/releases/download/test",
        "bar" => "https://github.com/homebrew/homebrew-core/releases/download/Test",
        "baz" => "https://github.com/homebrew/homebrew-other/releases/download/test",
        "qux" => "https://github.com/homebrew/homebrew-core/releases/download/test",
      }.to_h do |formula_name, root_url|
        [formula_name, {
          "bottle" => {
            "root_url" => root_url,
            "tags"     => {
              "arm64" => {
                "filename"       => "#{formula_name}-arm64.bottle.tar.gz",
                "local_filename" => "#{formula_name}-arm64.local.bottle.tar.gz",
              },
            },
          },
        }]
      end
      release_ids = {
        ["homebrew-core", "test"]  => 123,
        ["homebrew-core", "Test"]  => 456,
        ["homebrew-other", "test"] => 789,
      }
      allow(GitHub).to receive(:get_release).and_raise(GitHub::API::HTTPNotFoundError.new("not found"))
      allow(GitHub).to receive(:create_or_update_release) do |user, repo, tag, **kwargs|
        events << [user, repo, tag, kwargs]
        { "id" => release_ids.fetch([repo, tag]) }
      end
      allow(GitHub).to receive(:upload_release_asset) do |_, _, release_id, remote_file:, **|
        events << [remote_file, release_id]
      end

      described_class.new.upload_bottles(bottles_hash)

      expect(events).to eq([
        ["homebrew", "homebrew-core", "test", { draft: true }],
        ["foo-arm64.bottle.tar.gz", 123],
        ["qux-arm64.bottle.tar.gz", 123],
        ["homebrew", "homebrew-core", "test", { id: 123, draft: false }],
        ["homebrew", "homebrew-core", "Test", { draft: true }],
        ["bar-arm64.bottle.tar.gz", 456],
        ["homebrew", "homebrew-core", "Test", { id: 456, draft: false }],
        ["homebrew", "homebrew-other", "test", { draft: true }],
        ["baz-arm64.bottle.tar.gz", 789],
        ["homebrew", "homebrew-other", "test", { id: 789, draft: false }],
      ])
    end

    it "retries a partially uploaded shared draft without losing other assets" do
      events = []
      assets = T.let([{ "id" => 999, "name" => "notes.txt" }], T::Array[T::Hash[String, T.any(Integer, String)]])
      draft_release = { "id" => 456, "draft" => true, "assets" => assets }
      upload_attempts = Hash.new(0)
      directory = mktmpdir
      bottles_hash = %w[foo bar].to_h do |formula_name|
        local_file = directory/"#{formula_name}.bottle.tar.gz"
        local_file.write("bottle")
        [formula_name, {
          "bottle" => {
            "root_url" => "https://github.com/homebrew/homebrew-core/releases/download/test",
            "tags"     => {
              "arm64" => {
                "filename"       => "#{formula_name}.bottle.tar.gz",
                "local_filename" => local_file.to_s,
              },
            },
          },
        }]
      end
      allow(GitHub).to receive(:get_release).and_raise(GitHub::API::HTTPNotFoundError.new("not found"))
      allow(GitHub).to receive(:create_or_update_release)
        .with("homebrew", "homebrew-core", "test", draft: true)
        .and_raise(GitHub::API::Error.new("tag_name already exists"))
      allow(GitHub).to receive(:create_or_update_release)
        .with("homebrew", "homebrew-core", "test", id: 456, draft: false) do
          events << "publish release"
          draft_release
        end
      allow(GitHub).to receive(:get_draft_release).and_return(draft_release)
      allow(GitHub).to receive(:upload_release_asset) do |_, _, _, remote_file:, **|
        if assets.any? { |asset| asset.fetch("name") == remote_file }
          raise GitHub::API::ValidationFailedError.new("Validation Failed", ["already_exists"])
        end

        upload_attempts[remote_file] += 1
        upload_failed = remote_file == "bar.bottle.tar.gz" && upload_attempts[remote_file] == 1
        assets << {
          "id"    => ((remote_file == "foo.bottle.tar.gz") ? 100 : 200) + upload_attempts[remote_file],
          "name"  => remote_file,
          "state" => upload_failed ? "starter" : "uploaded",
        }
        events << "upload #{remote_file}"
        raise GitHub::API::Error, "upload failed" if upload_failed
      end
      allow(GitHub::API).to receive(:open_rest) do |url, **options|
        events << [url, options]
        assets.reject! { |asset| url.end_with?("/#{asset.fetch("id")}") }
      end

      begin
        described_class.new.upload_bottles(bottles_hash)
      rescue GitHub::API::Error => e
        events << e.message
      end
      described_class.new.upload_bottles(bottles_hash)

      expect([events, assets.map { |asset| asset.fetch("name") }]).to eq([
        [
          "upload foo.bottle.tar.gz",
          "upload bar.bottle.tar.gz",
          "upload failed",
          ["https://api.github.com/repos/homebrew/homebrew-core/releases/assets/101",
           { data: {}, request_method: :DELETE, scopes: ["repo"] }],
          "upload foo.bottle.tar.gz",
          ["https://api.github.com/repos/homebrew/homebrew-core/releases/assets/201",
           { data: {}, request_method: :DELETE, scopes: ["repo"] }],
          "upload bar.bottle.tar.gz",
          "publish release",
        ],
        ["notes.txt", "foo.bottle.tar.gz", "bar.bottle.tar.gz"],
      ])
    end

    it "does not replace assets on a published release" do
      bottles_hash = {
        "foo" => {
          "bottle" => {
            "root_url" => "https://github.com/homebrew/homebrew-core/releases/download/test",
            "tags"     => {
              "arm64" => {
                "filename"       => "foo.bottle.tar.gz",
                "local_filename" => "foo.bottle.tar.gz",
              },
            },
          },
        },
      }
      allow(GitHub).to receive(:get_release).and_return({
        "id"     => 456,
        "draft"  => false,
        "assets" => [{ "id" => 101, "name" => "foo.bottle.tar.gz" }],
      })
      allow(GitHub).to receive(:upload_release_asset)
        .and_raise(GitHub::API::ValidationFailedError.new("Validation Failed", ["already_exists"]))
      allow(GitHub::API).to receive(:open_rest).and_raise("Published assets must not be deleted")

      expect { described_class.new.upload_bottles(bottles_hash) }
        .to raise_error(GitHub::API::ValidationFailedError, /already_exists/)
    end

    it "keeps a draft asset when its replacement file is missing" do
      bottles_hash = {
        "foo" => {
          "bottle" => {
            "root_url" => "https://github.com/homebrew/homebrew-core/releases/download/test",
            "tags"     => {
              "arm64" => {
                "filename"       => "foo.bottle.tar.gz",
                "local_filename" => (mktmpdir/"missing.bottle.tar.gz").to_s,
              },
            },
          },
        },
      }
      allow(GitHub).to receive(:get_release).and_raise(GitHub::API::HTTPNotFoundError.new("not found"))
      allow(GitHub).to receive(:create_or_update_release)
        .and_raise(GitHub::API::Error.new("tag_name already exists"))
      allow(GitHub).to receive(:get_draft_release).and_return({
        "id"     => 456,
        "draft"  => true,
        "assets" => [{ "id" => 101, "name" => "foo.bottle.tar.gz" }],
      })
      allow(GitHub::API).to receive(:open_rest).and_raise("Draft asset must not be deleted")

      expect { described_class.new.upload_bottles(bottles_hash) }
        .to raise_error(GitHub::API::Error, /not a readable file/)
    end
  end
end
