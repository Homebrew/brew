# typed: true
# frozen_string_literal: true

require "api"
require "openssl"

RSpec.describe Homebrew::API do
  let(:json) { '{"foo":"bar"}' }
  let(:json_hash) { JSON.parse(json) }
  let(:json_invalid) { '{"foo":"bar"' }

  def mock_curl_download(stdout:)
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].write stdout
    end
  end

  describe "::with_no_api_env" do
    it "sets the API environment for the duration of the block" do
      ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")
      ENV.delete("HOMEBREW_AUTOMATICALLY_SET_NO_INSTALL_FROM_API")

      values = described_class.with_no_api_env do
        [ENV.fetch("HOMEBREW_NO_INSTALL_FROM_API", nil),
         ENV.fetch("HOMEBREW_AUTOMATICALLY_SET_NO_INSTALL_FROM_API", nil)]
      end

      expect(values).to eq(["1", "1"])
      expect(ENV.fetch("HOMEBREW_NO_INSTALL_FROM_API", nil)).to be_nil
    end
  end

  describe "::formula_name?" do
    before do
      allow(Homebrew::API::Internal).to receive(:formula_name?) { |name| name == "foo" }
    end

    it "returns true for a core formula name" do
      expect(described_class.formula_name?("foo")).to be true
    end

    it "returns false for an unknown name" do
      expect(described_class.formula_name?("bar")).to be false
    end
  end

  describe "::cask_token?" do
    before do
      allow(Homebrew::API::Internal).to receive(:cask_name?) { |token| token == "foo" }
    end

    it "returns true for a core cask token" do
      expect(described_class.cask_token?("foo")).to be true
    end

    it "returns false for an unknown token" do
      expect(described_class.cask_token?("bar")).to be false
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

  describe "::fetch_json_api_file with a JWS endpoint" do
    def self.jws_test_key
      @jws_test_key ||= OpenSSL::PKey::RSA.new(2048)
    end

    let!(:cache_dir) { mktmpdir }
    let(:target) { cache_dir/"internal/packages.test.jws.json" }
    let(:payload_cache) { cache_dir/"internal/packages.test.jws.json.payload" }
    let(:private_key) { self.class.jws_test_key }
    let(:protected_b64) { urlsafe_encode64('{"alg":"PS512","b64":false}') }

    def urlsafe_encode64(value)
      [value].pack("m0").tr("+/", "-_")
    end

    def sign_payload(payload)
      urlsafe_encode64(
        private_key.sign_pss("SHA512", "#{protected_b64}.#{payload}", salt_length: :digest, mgf1_hash: "SHA512"),
      )
    end

    def envelope_json(payload, signature: sign_payload(payload))
      JSON.generate({
        "payload"    => payload,
        "signatures" => [{
          "header"    => { "kid" => "homebrew-1" },
          "protected" => protected_b64,
          "signature" => signature,
        }],
      })
    end

    def write_payload_cache(payload, signature: sign_payload(payload))
      stat = target.stat
      header = JSON.generate({
        "protected"       => protected_b64,
        "signature"       => signature,
        "source_size"     => stat.size,
        "source_mtime_ns" => (stat.mtime.to_r * 1_000_000_000).to_i,
      })
      payload_cache.binwrite("#{header}\n#{payload}")
    end

    def fetch_target
      described_class.fetch_json_api_file("internal/packages.test.jws.json", target:, stale_seconds: 3600).first
    end

    before do
      stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)
      allow(described_class).to receive(:jws_public_key_pem).and_return(private_key.public_key.to_pem)
      target.dirname.mkpath
      target.write envelope_json('{"foo":"bar"}')
    end

    it "verifies the envelope and writes a payload cache" do
      expect(fetch_target).to eq("foo" => "bar")
      expect(payload_cache).to exist
    end

    it "does not write a payload cache for endpoints without one" do
      other_target = cache_dir/"internal/other.jws.json"
      other_target.write envelope_json('{"foo":"bar"}')

      data, = described_class.fetch_json_api_file("internal/other.jws.json", target:        other_target,
                                                                             stale_seconds: 3600)
      expect(data).to eq("foo" => "bar")
      expect(Pathname("#{other_target}.payload")).not_to exist
    end

    it "loads a current payload cache instead of the envelope" do
      write_payload_cache('{"foo":"baz"}')
      expect(fetch_target).to eq("foo" => "baz")
    end

    it "falls back to the envelope when the payload cache does not match the file" do
      write_payload_cache('{"foo":"baz"}')
      FileUtils.touch target, mtime: Time.now + 10
      expect(fetch_target).to eq("foo" => "bar")
    end

    it "falls back to the envelope when the payload cache signature does not verify" do
      write_payload_cache('{"foo":"baz"}', signature: sign_payload('{"foo":"qux"}'))
      expect(fetch_target).to eq("foo" => "bar")
    end

    it "falls back to the envelope when the payload cache is corrupt" do
      payload_cache.write "not json"
      expect(fetch_target).to eq("foo" => "bar")
    end

    it "falls back to the envelope when the payload cache header is not a JSON object" do
      payload_cache.binwrite("123\n{\"foo\":\"baz\"}")
      expect(fetch_target).to eq("foo" => "bar")
    end

    it "raises when the envelope signature does not verify" do
      target.write envelope_json('{"foo":"bar"}', signature: sign_payload('{"foo":"evil"}'))
      expect { fetch_target }.to raise_error(SystemExit)
        .and output(/Failed to verify integrity \(signature mismatch\)/).to_stderr
    end
  end

  describe "::fetch_api_files!" do
    it "does not initialise downloads when the API cache is current" do
      target = mktmpdir/"packages.json"
      target.write json
      allow(Homebrew::API::Internal).to receive(:cached_packages_json_file_path).and_return(target)
      allow(Homebrew::EnvConfig).to receive(:no_auto_update?).and_return(true)

      expect(Homebrew::API::Internal).not_to receive(:fetch_packages_api!)
      described_class.fetch_api_files!
    end

    it "handles a missing API cache before refusing root downloads" do
      queue = instance_double(Homebrew::DownloadQueue, fetch: nil, shutdown: nil)
      allow(Homebrew::DownloadQueue).to receive(:new).and_return(queue)
      allow(Homebrew::API::Internal).to receive(:cached_packages_json_file_path).and_return(mktmpdir/"packages.json")
      allow(Homebrew).to receive(:running_as_root_but_not_owned_by_root?).and_return(true)

      expect(Homebrew::API::Internal).to receive(:fetch_packages_api!).and_return([{}, false])
      described_class.fetch_api_files!
    end
  end

  describe "::urlsafe_decode64" do
    it "decodes unpadded URL-safe base64" do
      expect(described_class.instance_eval { urlsafe_decode64("SGVsbG8") }).to eq("Hello")
    end

    it "rejects invalid base64" do
      expect { described_class.instance_eval { urlsafe_decode64("a") } }.to raise_error(ArgumentError)
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
    let(:cache_dir) { mktmpdir }
    let(:target) { cache_dir/"internal/executables.txt" }
    let(:source) { cache_dir/"internal/packages.jws.json" }
    let(:formulae) { { "foo" => { "executables" => ["foo-bin"] } } }

    def write_executables_file!(regenerate:)
      described_class.write_executables_file!(regenerate:, source:) { formulae }
    end

    before do
      stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)
      source.dirname.mkpath
      source.write "{}"
    end

    it "writes the executables database when it does not exist" do
      expect(write_executables_file!(regenerate: false)).to be true
      expect(target.read).to eq("foo:foo-bin\n")
    end

    it "does not rebuild an executables database newer than its source when not regenerating" do
      target.write "stale:stale-bin\n"
      FileUtils.touch target, mtime: source.mtime + 1

      expect(write_executables_file!(regenerate: false)).to be false
      expect(target.read).to eq("stale:stale-bin\n")
    end

    it "rebuilds the executables database when the source is newer" do
      target.write "stale:stale-bin\n"
      FileUtils.touch source, mtime: target.mtime + 1

      expect(write_executables_file!(regenerate: false)).to be true
      expect(target.read).to eq("foo:foo-bin\n")
    end

    it "rewrites the executables database when regenerating" do
      target.write "stale:stale-bin\n"
      FileUtils.touch target, mtime: source.mtime + 1

      expect(write_executables_file!(regenerate: true)).to be true
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
