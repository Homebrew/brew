# typed: true
# frozen_string_literal: true

require "api"
require "lock_file"
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

    context "when running as root in a user-owned installation" do
      before do
        allow(Homebrew).to receive(:running_as_root_but_not_owned_by_root?).and_return(true)
      end

      it "uses the Homebrew owner's cache in the suggested services retry" do
        target = cache_dir/"missing.json"
        stub_const("HOMEBREW_BREW_FILE", Pathname("/brew prefix/bin/brew"))

        expect do
          described_class.fetch_json_api_file("missing.json", target:)
        end.to raise_error(SystemExit).and output(<<~EOS).to_stderr
          Error: Root cannot download the missing API cache file #{target.to_s.dump}.
          For system services, populate the Homebrew owner's private cache and retry.
            /brew\\ prefix/bin/brew as-brew-user info
            sudo HOMEBREW_CACHE="$(/brew\\ prefix/bin/brew as-brew-user --cache)" /brew\\ prefix/bin/brew services ...
        EOS
      end

      it "preserves malformed JSON instead of downloading it again" do
        target = cache_dir/"bar.json"
        mock_curl_download stdout: json

        expect do
          described_class.fetch_json_api_file("bar.json", target:)
        end.to raise_error(SystemExit).and output(/invalid API cache file/).to_stderr
        expect(target.read).to eq "tmp"
      end

      it "preserves a cached file that fails signature verification" do
        target = cache_dir/"foo.jws.json"
        target.write json

        expect do
          described_class.fetch_json_api_file("foo.jws.json", target:)
        end.to raise_error(SystemExit).and output(/Failed to verify integrity/).to_stderr
        expect(target.read).to eq json
      end
    end

    it "loads the configured curlrc once per download", :needs_utils_curl do
      ENV["HOMEBREW_CURLRC"] = (cache_dir/"curlrc").to_s
      curl_args = []
      allow(Utils::Curl).to receive(:system_command) do |_command, args:, **|
        curl_args.replace(args)
        File.write(args.fetch(args.index("--output") + 1), json)
        instance_double(SystemCommand::Result, success?: true, stdout: "200", assert_success!: nil)
      end

      described_class.fetch_json_api_file("foo.json", target: cache_dir/"foo.json")

      expect(curl_args.count("--config")).to eq(1)
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

    context "with a stale cached file" do
      let(:target) { cache_dir/"bar.json" }
      let(:etag_path) { Pathname("#{target}.etag") }
      let(:etag_url_path) { Pathname("#{etag_path}.url") }
      let(:new_etag_path) { Pathname("#{target}.etag.new") }
      let(:curl_args) { [] }

      before do
        stub_const("HOMEBREW_CURL_SUPPORTS_ETAGS", true)
        target.write json
        FileUtils.touch(target, mtime: Time.now - 7200)
        etag_url_path.write "#{Homebrew::EnvConfig.api_domain}/bar.json"
      end

      def stub_curl(status:, etag: "")
        allow(Utils::Curl).to receive(:curl_download) do |*args, to:, **|
          curl_args.replace(args)
          File.write(args.fetch(args.index("--etag-save") + 1), etag) if etag && args.include?("--etag-save")
          to.write json if status == 200
          SystemCommand::Result.new(["curl"], [[:stdout, status.to_s]],
                                    instance_double(Process::Status, success?: true, exitstatus: 0),
                                    secrets: [])
        end
      end

      def fetch
        described_class.fetch_json_api_file("bar.json", target:, stale_seconds: 3600)
      end

      it "sends the saved ETag instead of the cache mtime and stores the new one" do
        etag_path.write 'W/"old"'
        stub_curl(status: 200, etag: 'W/"new"')
        fetch
        expect(curl_args).to include("--etag-compare", etag_path.to_s)
        expect(curl_args).not_to include("--time-cond")
        expect(etag_path.read).to eq 'W/"new"'
      end

      it "downloads a fresh body and saves the ETag when none is saved" do
        etag_url_path.unlink
        stub_curl(status: 200, etag: 'W/"new"')
        fetch
        expect([curl_args.grep(/--(?:time-cond|etag-compare)/), etag_path.read, etag_url_path.read])
          .to eq [[], 'W/"new"', "#{Homebrew::EnvConfig.api_domain}/bar.json"]
      end

      it "downloads a fresh body when the saved ETag is empty" do
        etag_path.write ""
        stub_curl(status: 200, etag: 'W/"new"')
        fetch
        expect(curl_args).not_to include("--time-cond", "--etag-compare")
      end

      it "keeps the saved ETag, refreshes the mtime and leaves no temp file on a 304" do
        etag_path.write 'W/"old"'
        stub_curl(status: 304)
        fetch
        expect(etag_path.read).to eq 'W/"old"'
        expect(new_etag_path).not_to exist
        expect(target.mtime).to be > Time.now - 60
      end

      it "ignores a leftover temp ETag from an earlier run" do
        etag_path.write 'W/"old"'
        new_etag_path.write 'W/"leftover"'
        stub_curl(status: 304, etag: nil)
        fetch
        expect(etag_path.read).to eq 'W/"old"'
      end

      it "preserves an in-progress ETag when using a fresh cached file" do
        FileUtils.touch(target)
        new_etag_path.write 'W/"new"'
        fetch
        expect(new_etag_path).to exist
      end

      test_each([false, true]) do |corrupt|
        it "holds the shared download lock when refreshing the cache (corrupt: #{corrupt})" do
          if corrupt
            target.write json_invalid
            FileUtils.touch(target)
          end
          lock = DownloadLock.new(target)
          allow(Utils::Curl).to receive(:curl_download) do |*_, to:, **|
            expect { lock.lock }.to raise_error(OperationInProgressError)
            to.write json
          end
          fetch
        ensure
          lock&.unlock
        end
      end

      it "removes the saved ETag when a 200 carries none" do
        etag_path.write 'W/"old"'
        stub_curl(status: 200)
        fetch
        expect(etag_path).not_to exist
      end

      it "keeps the saved ETag when the download fails" do
        etag_path.write 'W/"old"'
        allow(Utils::Curl).to receive(:curl_download).and_raise(ErrorDuringExecution.new(["curl"], status: 1))
        expect { fetch }.to output(/falling back to cached version/).to_stderr
        expect(etag_path.read).to eq 'W/"old"'
      end

      it "preserves the cached body, ETag and mtime after a partial download" do
        etag_path.write 'W/"old"'
        mtime = target.mtime
        allow(described_class).to receive(:opoo)
        allow(Utils::Curl).to receive(:curl_download) do |*args, to:, **|
          to.write '{"partial":'
          File.write(args.fetch(args.index("--etag-save") + 1), 'W/"partial"')
          raise ErrorDuringExecution.new(["curl"], status: 18)
        end

        fetch

        expect([target.read, etag_path.read, target.mtime, new_etag_path.exist?, Pathname("#{target}.new").exist?])
          .to eq [json, 'W/"old"', mtime, false, false]
      end

      test_each([false, true]) do |supports_etags|
        it "retries a receive error without conditions with ETag support #{supports_etags}" do
          stub_const("HOMEBREW_CURL_SUPPORTS_ETAGS", supports_etags)
          etag_path.write 'W/"old"'
          requests = []
          allow(Utils::Curl).to receive(:curl_download) do |*args, to:, **|
            requests << args
            if args.include?("--etag-compare") || args.include?("--time-cond")
              raise ErrorDuringExecution.new(["curl"], status: 56)
            end

            to.write '{"foo":"updated"}'
            SystemCommand::Result.new(["curl"], [[:stdout, "200"]],
                                      instance_double(Process::Status, success?: true, exitstatus: 0),
                                      secrets: [])
          end

          fetch

          expect([requests.length, target.read, etag_path.exist?]).to eq [2, '{"foo":"updated"}', false]
        end
      end

      it "ignores an ETag saved for a different API domain" do
        etag_path.write 'W/"old"'
        etag_url_path.write "https://mirror.example/api/bar.json"
        stub_curl(status: 200, etag: 'W/"new"')
        fetch
        expect(curl_args).not_to include("--time-cond", "--etag-compare")
      end

      it "ignores an ETag whose origin is unknown" do
        etag_path.write 'W/"old"'
        etag_url_path.unlink
        stub_curl(status: 200, etag: 'W/"new"')
        fetch
        expect(curl_args).not_to include("--time-cond", "--etag-compare")
      end

      it "keeps the saved ETag after a 304 with curl older than 7.68.0" do
        stub_const("HOMEBREW_CURL_SUPPORTS_ETAGS", false)
        etag_path.write 'W/"old"'
        stub_curl(status: 304)
        fetch
        expect(etag_path).to exist
      end

      it "uses only --time-cond and removes the saved ETag after a 200 when curl is older than 7.68.0" do
        stub_const("HOMEBREW_CURL_SUPPORTS_ETAGS", false)
        etag_path.write 'W/"old"'
        stub_curl(status: 200)
        fetch
        expect(curl_args).to include("--time-cond", target.to_s)
        expect(curl_args.grep(/etag/)).to be_empty
        expect(etag_path).not_to exist
      end

      it "downloads unconditionally from the fallback API domain" do
        allow(Homebrew::EnvConfig).to receive(:api_domain).and_return("https://example.invalid/api")
        etag_url_path.write "https://example.invalid/api/bar.json"
        etag_path.write 'W/"old"'
        requests = []
        allow(Utils::Curl).to receive(:curl_download) do |*args, to:, **|
          requests << args.dup
          raise ErrorDuringExecution.new(["curl"], status: 1) if requests.length == 1

          to.write json
          SystemCommand::Result.new(["curl"], [[:stdout, "200"]],
                                    instance_double(Process::Status, success?: true, exitstatus: 0),
                                    secrets: [])
        end
        fetch
        expect(requests.fetch(0)).to include("--etag-compare", "--etag-save")
        expect(requests.fetch(1)).not_to include("--time-cond")
        expect(requests.fetch(1).grep(/etag/)).to be_empty
        expect(etag_path).not_to exist
      end
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

    it "measures how old the signed packages were when the cache was refreshed" do
      generated_at = 1_714_056_000
      target.write envelope_json(JSON.generate(metadata: { generated_at: }))
      FileUtils.touch target, mtime: Time.at(generated_at) + (48 * 3600)
      allow(Homebrew::API::Internal).to receive(:cached_packages_json_file_path).and_return(target)

      expect(described_class.cached_packages_delay_hours).to eq(48)
    end

    it "ignores package timestamps with an invalid signature" do
      payload = JSON.generate(metadata: { generated_at: 1_714_056_000 })
      target.write envelope_json(payload, signature: sign_payload("{}"))
      allow(Homebrew::API::Internal).to receive(:cached_packages_json_file_path).and_return(target)

      expect(described_class.cached_packages_delay_hours).to be_nil
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
    it "downloads executables.txt from the homebrew-core package" do
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
        "https://ghcr.io/v2/homebrew/core/command-not-found/executables/manifests/latest",
        show_error: false
      ).and_return(instance_double(SystemCommand::Result, stdout: JSON.generate(manifest), success?: true))
      expect(Utils::Curl).to receive(:curl_download).with(
        "--fail",
        "--header", "Authorization: Bearer QQ==",
        "https://ghcr.io/v2/homebrew/core/command-not-found/executables/blobs/sha256:abc123",
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
