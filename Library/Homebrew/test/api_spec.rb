# typed: true
# frozen_string_literal: true

require "api"

RSpec.describe Homebrew::API do
  let(:text) { "foo" }
  let(:json) { '{"foo":"bar"}' }
  let(:json_hash) { JSON.parse(json) }
  let(:json_invalid) { '{"foo":"bar"' }

  def mock_curl_output(stdout: "", success: true)
    curl_output = instance_double(SystemCommand::Result, stdout:, success?: success)
    allow(Utils::Curl).to receive(:curl_output).and_return curl_output
  end

  def mock_curl_download(stdout:)
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].write stdout
    end
  end

  describe "::fetch" do
    it "fetches a JSON file" do
      mock_curl_output stdout: json
      fetched_json = described_class.fetch("foo.json")
      expect(fetched_json).to eq json_hash
    end

    it "raises an error if the file does not exist" do
      mock_curl_output success: false
      expect { described_class.fetch("bar.txt") }.to raise_error(ArgumentError, /No file found/)
    end

    it "raises an error if the JSON file is invalid" do
      mock_curl_output stdout: text
      expect { described_class.fetch("baz.txt") }.to raise_error(ArgumentError, /Invalid JSON file/)
    end
  end

  describe "::fetch_json_api_file" do
    let!(:cache_dir) { mktmpdir }

    before do
      (cache_dir/"bar.json").write "tmp"
    end

    it "fetches a JSON file" do
      mock_curl_download stdout: json
      fetched_json, = described_class.fetch_json_api_file("foo.json", target: cache_dir/"foo.json")
      expect(fetched_json).to eq json_hash
    end

    it "updates an existing JSON file" do
      mock_curl_download stdout: json
      fetched_json, = described_class.fetch_json_api_file("bar.json", target: cache_dir/"bar.json")
      expect(fetched_json).to eq json_hash
    end

    it "raises an error if the JSON file is invalid" do
      mock_curl_download stdout: json_invalid
      expect do
        described_class.fetch_json_api_file("baz.json", target: cache_dir/"baz.json")
      end.to raise_error(SystemExit)
    end

    it "does not refresh the cache mtime when the download fails" do
      target = cache_dir/"bar.json"
      target.write json
      stale_mtime = Time.now - 7200
      FileUtils.touch(target, mtime: stale_mtime)

      allow(Utils::Curl).to receive(:curl_download).and_raise(ErrorDuringExecution.new(["curl"], status: 1))

      expect do
        described_class.fetch_json_api_file(
          "bar.json",
          target:        target,
          stale_seconds: 3600,
        )
      end.to output(/update failed, falling back to cached version/).to_stderr

      expect(target.mtime.to_i).to eq stale_mtime.to_i
    end

    it "refreshes the cache mtime when a fallback to the default API domain succeeds" do
      target = cache_dir/"bar.json"
      target.write json
      stale_mtime = Time.now - 7200
      FileUtils.touch(target, mtime: stale_mtime)

      allow(Homebrew::EnvConfig).to receive(:api_domain).and_return("https://example.invalid/api")

      requested_urls = []
      allow(Utils::Curl).to receive(:curl_download) do |*args, **kwargs|
        requested_urls << args.last
        raise ErrorDuringExecution.new(["curl"], status: 1) if requested_urls.length == 1

        kwargs[:to].write json
      end

      described_class.fetch_json_api_file(
        "bar.json",
        target:        target,
        stale_seconds: 3600,
      )

      expect(requested_urls).to eq([
        "https://example.invalid/api/bar.json",
        "#{HOMEBREW_API_DEFAULT_DOMAIN}/bar.json",
      ])
      expect(target.mtime.to_i).to be > stale_mtime.to_i
    end
  end

  describe "::download_executables_file_from_github_packages!" do
    it "downloads executables.txt from the GitHub Packages OCI artifact" do
      target = mktmpdir/"executables.txt"
      stub_const("HOMEBREW_GITHUB_PACKAGES_AUTH", "Bearer QQ==")
      manifest = {
        "layers" => [{
          "digest"      => "sha256:abc123",
          "annotations" => {
            "org.opencontainers.image.title" => "executables.txt",
          },
        }],
      }

      expect(Utils::Curl).to receive(:curl_output).with(
        "--fail", "--location",
        "--header", "Accept: application/vnd.oci.image.manifest.v1+json",
        "--header", "Authorization: Bearer QQ==",
        "https://ghcr.io/v2/homebrew/command-not-found/executables/manifests/latest",
        show_error: false
      ).and_return(instance_double(SystemCommand::Result, stdout: JSON.generate(manifest), success?: true))
      expect(Utils::Curl).to receive(:curl_download).with(
        "--fail",
        "--header", "Authorization: Bearer QQ==",
        "https://ghcr.io/v2/homebrew/command-not-found/executables/blobs/sha256:abc123",
        to:         target,
        show_error: false
      ) { |*_args, **kwargs| kwargs[:to].write "foo:foo-bin\n" }

      expect(described_class.download_executables_file_from_github_packages!(target)).to be true
      expect(target.read).to eq("foo:foo-bin\n")
    end
  end

  describe "::write_executables_file!" do
    it "handles the executables database being removed before comparison" do
      cache_dir = mktmpdir
      target = cache_dir/"internal/executables.txt"
      target.dirname.mkpath
      target.write "stale:stale-bin\n"
      stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)

      removed = T.let(false, T::Boolean)
      allow_any_instance_of(Pathname).to receive(:read).and_wrap_original do |method, *args|
        if !removed && method.receiver == target
          removed = true
          target.unlink
          raise Errno::ENOENT
        end

        method.call(*args)
      end

      expect(described_class.write_executables_file!(
               { "foo" => { "executables" => ["foo-bin"] } },
               regenerate: false,
             )).to be true
      expect(target.read).to eq("foo:foo-bin\n")
    end
  end

  describe "::tap_from_source_download" do
    let(:api_cache_root) { Homebrew::API::HOMEBREW_CACHE_API_SOURCE }
    let(:cache_path) do
      api_cache_root/"Homebrew"/"homebrew-core"/"cf5c386c1fa2cb54279d78c0990dd7a0fa4bc327"/"Formula"/"foo.rb"
    end

    context "when given a path inside the API source cache" do
      it "returns the corresponding tap" do
        expect(described_class.tap_from_source_download(cache_path)).to eq CoreTap.instance
      end
    end

    context "when given a path that is not inside the API source cache" do
      let(:api_cache_root) { mktmpdir }

      it "returns nil" do
        expect(described_class.tap_from_source_download(cache_path)).to be_nil
      end
    end

    context "when given a relative path that is not inside the API source cache" do
      it "returns nil" do
        expect(described_class.tap_from_source_download(Pathname("../foo.rb"))).to be_nil
      end
    end
  end

  describe "::merge_variations" do
    let(:arm64_sequoia_tag) { Utils::Bottles::Tag.new(system: :sequoia, arch: :arm) }
    let(:sonoma_tag) { Utils::Bottles::Tag.new(system: :sonoma, arch: :intel) }
    let(:x86_64_linux_tag) { Utils::Bottles::Tag.new(system: :linux, arch: :intel) }

    let(:json) do
      {
        "name"       => "foo",
        "foo"        => "bar",
        "baz"        => ["test1", "test2"],
        "variations" => {
          "arm64_sequoia" => { "foo" => "new" },
          :sonoma         => { "baz" => ["new1", "new2", "new3"] },
        },
      }
    end

    let(:arm64_sequoia_result) do
      {
        "name" => "foo",
        "foo"  => "new",
        "baz"  => ["test1", "test2"],
      }
    end

    let(:sonoma_result) do
      {
        "name" => "foo",
        "foo"  => "bar",
        "baz"  => ["new1", "new2", "new3"],
      }
    end

    it "returns the original JSON if no variations are found" do
      result = described_class.merge_variations(arm64_sequoia_result, bottle_tag: arm64_sequoia_tag)
      expect(result).to eq arm64_sequoia_result
    end

    it "returns the original JSON if no variations are found for the current system" do
      result = described_class.merge_variations(arm64_sequoia_result)
      expect(result).to eq arm64_sequoia_result
    end

    it "returns the original JSON without the variations if no matching variation is found" do
      result = described_class.merge_variations(json, bottle_tag: x86_64_linux_tag)
      expect(result).to eq json.except("variations")
    end

    it "returns the original JSON without the variations if no matching variation is found for the current system" do
      Homebrew::SimulateSystem.with(os: :linux, arch: :intel) do
        result = described_class.merge_variations(json)
        expect(result).to eq json.except("variations")
      end
    end

    it "returns the JSON with the matching variation applied from a string key" do
      result = described_class.merge_variations(json, bottle_tag: arm64_sequoia_tag)
      expect(result).to eq arm64_sequoia_result
    end

    it "returns the JSON with the matching variation applied from a string key for the current system" do
      Homebrew::SimulateSystem.with(os: :sequoia, arch: :arm) do
        result = described_class.merge_variations(json)
        expect(result).to eq arm64_sequoia_result
      end
    end

    it "returns the JSON with the matching variation applied from a symbol key" do
      result = described_class.merge_variations(json, bottle_tag: sonoma_tag)
      expect(result).to eq sonoma_result
    end

    it "returns the JSON with the matching variation applied from a symbol key for the current system" do
      Homebrew::SimulateSystem.with(os: :sonoma, arch: :intel) do
        result = described_class.merge_variations(json)
        expect(result).to eq sonoma_result
      end
    end
  end
end
