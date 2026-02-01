# typed: strict
# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Attestation do
  let(:fake_gh) { Pathname.new("/extremely/fake/gh") }
  let(:fake_old_gh) { Pathname.new("/extremely/fake/old/gh") }
  let(:fake_gh_creds) { "fake-gh-api-token" }
  let(:fake_error_status) { instance_double(Process::Status, exitstatus: 1, termsig: nil) }
  let(:fake_auth_status) { instance_double(Process::Status, exitstatus: 4, termsig: nil) }
  let(:fake_curl_error_status) { instance_double(Process::Status, exitstatus: 22, termsig: nil) }
  let(:cached_download) { "/fake/cached/download" }
  let(:fake_bottle_filename) do
    instance_double(Bottle::Filename, name: "fakebottle", version: "1.0",
   to_s: "fakebottle--1.0.faketag.bottle.tar.gz")
  end
  let(:fake_bottle_url) { "https://example.com/#{fake_bottle_filename}" }
  let(:fake_bottle_tag) { instance_double(Utils::Bottles::Tag, to_sym: :faketag) }
  let(:fake_all_bottle_tag) { instance_double(Utils::Bottles::Tag, to_sym: :all) }
  let(:fake_digest) { "a" * 64 }
  let(:fake_bundle_url_template) { "https://mirror.internal/bundles/{hexdigest}.jsonl" }
  let(:fake_oci_bundle_url_template) { "https://mirror.internal/bundles/{digest}.jsonl" }
  let(:fake_trusted_root_url) { "https://mirror.internal/trusted_root.json" }
  let(:fake_checksum) { instance_double(Checksum, hexdigest: fake_digest) }
  let(:fake_resource) { instance_double(Resource, checksum: fake_checksum) }
  let(:fake_bottle) do
    instance_double(Bottle, cached_download:, filename: fake_bottle_filename, url: fake_bottle_url,
                    tag: fake_bottle_tag)
  end
  let(:fake_bottle_with_resource) do
    instance_double(Bottle, cached_download:, filename: fake_bottle_filename, url: fake_bottle_url,
                    tag: fake_bottle_tag, resource: fake_resource)
  end
  let(:fake_all_bottle) do
    instance_double(Bottle, cached_download:, filename: fake_bottle_filename, url: fake_bottle_url,
                    tag: fake_all_bottle_tag)
  end
  let(:fake_result_invalid_json) { instance_double(SystemCommand::Result, stdout: "\"invalid JSON") }
  let(:fake_result_json_resp) do
    instance_double(SystemCommand::Result,
                    stdout: JSON.dump([
                      { verificationResult: {
                        verifiedTimestamps: [{ timestamp: "2024-03-13T00:00:00Z" }],
                        statement:          { subject: [{ name: fake_bottle_filename.to_s }] },
                      } },
                    ]))
  end
  let(:fake_result_json_resp_multi_subject) do
    instance_double(SystemCommand::Result,
                    stdout: JSON.dump([
                      { verificationResult: {
                        verifiedTimestamps: [{ timestamp: "2024-03-13T00:00:00Z" }],
                        statement:          { subject: [{ name: "nonsense" }, { name: fake_bottle_filename.to_s }] },
                      } },
                    ]))
  end
  let(:fake_result_json_resp_backfill) do
    digest = Digest::SHA256.hexdigest(fake_bottle_url)
    instance_double(SystemCommand::Result,
                    stdout: JSON.dump([
                      { verificationResult: {
                        verifiedTimestamps: [{ timestamp: "2024-03-13T00:00:00Z" }],
                        statement:          {
                          subject: [{ name: "#{digest}--#{fake_bottle_filename}" }],
                        },
                      } },
                    ]))
  end
  let(:fake_result_json_resp_too_new) do
    instance_double(SystemCommand::Result,
                    stdout: JSON.dump([
                      { verificationResult: {
                        verifiedTimestamps: [{ timestamp: "2024-03-15T00:00:00Z" }],
                        statement:          { subject: [{ name: fake_bottle_filename.to_s }] },
                      } },
                    ]))
  end
  let(:fake_json_resp_wrong_sub) do
    instance_double(SystemCommand::Result,
                    stdout: JSON.dump([
                      { verificationResult: {
                        verifiedTimestamps: [{ timestamp: "2024-03-13T00:00:00Z" }],
                        statement:          { subject: [{ name: "wrong-subject.tar.gz" }] },
                      } },
                    ]))
  end

  describe "::gh_executable" do
    it "calls ensure_executable" do
      expect(described_class).to receive(:ensure_executable!)
        .with("gh", reason: "verifying attestations", latest: true)
        .and_return(fake_gh)

      described_class.gh_executable
    end
  end

  describe "::offline_verification?" do
    it "returns true when HOMEBREW_ATTESTATION_BUNDLE_URL is set" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_bundle_url_template)

      expect(described_class.offline_verification?).to be true
    end

    it "returns false when HOMEBREW_ATTESTATION_BUNDLE_URL is not set" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(nil)

      expect(described_class.offline_verification?).to be false
    end

    it "returns false when HOMEBREW_ATTESTATION_BUNDLE_URL is empty" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return("")

      expect(described_class.offline_verification?).to be false
    end
  end

  describe "::url?" do
    it "returns true for http URLs" do
      expect(described_class.url?("http://example.com/file")).to be true
    end

    it "returns true for https URLs" do
      expect(described_class.url?("https://example.com/file")).to be true
    end

    it "returns true for file URLs" do
      expect(described_class.url?("file:///path/to/file")).to be true
    end

    it "returns false for local paths" do
      expect(described_class.url?("/path/to/file")).to be false
      expect(described_class.url?("./relative/path")).to be false
      expect(described_class.url?("relative/path")).to be false
    end

    it "is case-insensitive for scheme matching" do
      expect(described_class.url?("HTTP://example.com")).to be true
      expect(described_class.url?("HTTPS://example.com")).to be true
      expect(described_class.url?("HtTpS://example.com")).to be true
    end
  end

  describe "::detect_digest_algorithm" do
    it "detects SHA256 from 64-character hex strings" do
      expect(described_class.detect_digest_algorithm("a" * 64)).to eq :sha256
      expect(described_class.detect_digest_algorithm("0123456789abcdef" * 4)).to eq :sha256
    end

    it "is case-insensitive" do
      expect(described_class.detect_digest_algorithm("A" * 64)).to eq :sha256
    end

    it "returns nil for invalid lengths" do
      expect(described_class.detect_digest_algorithm("a" * 32)).to be_nil
      expect(described_class.detect_digest_algorithm("a" * 63)).to be_nil
      expect(described_class.detect_digest_algorithm("a" * 65)).to be_nil
      expect(described_class.detect_digest_algorithm("a" * 128)).to be_nil
    end

    it "returns nil for non-hex characters" do
      expect(described_class.detect_digest_algorithm("g" * 64)).to be_nil
    end

    it "returns nil for empty strings" do
      expect(described_class.detect_digest_algorithm("")).to be_nil
    end
  end

  describe "::valid_digest?" do
    it "returns true for valid 64-character lowercase hex strings" do
      expect(described_class.valid_digest?("a" * 64)).to be true
      expect(described_class.valid_digest?("0123456789abcdef" * 4)).to be true
    end

    it "returns true for valid 64-character uppercase hex strings" do
      expect(described_class.valid_digest?("A" * 64)).to be true
      expect(described_class.valid_digest?("0123456789ABCDEF" * 4)).to be true
    end

    it "returns true for mixed case hex strings" do
      expect(described_class.valid_digest?("aAbBcCdDeEfF0123456789#{"0" * 42}")).to be true
    end

    it "returns false for strings shorter than 64 characters" do
      expect(described_class.valid_digest?("a" * 63)).to be false
      expect(described_class.valid_digest?("a" * 32)).to be false
    end

    it "returns false for strings longer than 64 characters" do
      expect(described_class.valid_digest?("a" * 65)).to be false
    end

    it "returns false for non-hex characters" do
      expect(described_class.valid_digest?("g" * 64)).to be false
      expect(described_class.valid_digest?("z" * 64)).to be false
      expect(described_class.valid_digest?("#{"a" * 63}!")).to be false
    end

    it "returns false for empty strings" do
      expect(described_class.valid_digest?("")).to be false
    end
  end

  describe "::atomic_write" do
    it "writes content atomically via temp file" do
      Dir.mktmpdir do |dir|
        path = Pathname.new(dir)/"test_file.txt"
        content = "test content"

        described_class.atomic_write(path) do |tmp_path|
          tmp_path.write(content)
        end

        expect(path.read).to eq content
      end
    end

    it "cleans up temp file on success" do
      Dir.mktmpdir do |dir|
        path = Pathname.new(dir)/"test_file.txt"
        tmp_files_before = Dir.glob("#{dir}/*.tmp")

        described_class.atomic_write(path) do |tmp_path|
          tmp_path.write("content")
        end

        tmp_files_after = Dir.glob("#{dir}/*.tmp")
        expect(tmp_files_after).to eq tmp_files_before
      end
    end

    it "cleans up temp file on error" do
      Dir.mktmpdir do |dir|
        path = Pathname.new(dir)/"test_file.txt"

        expect do
          described_class.atomic_write(path) do |tmp_path|
            tmp_path.write("content")
            raise "test error"
          end
        end.to raise_error(RuntimeError, "test error")

        tmp_files = Dir.glob("#{dir}/*.tmp")
        expect(tmp_files).to be_empty
        expect(path.exist?).to be false
      end
    end
  end

  describe "::fetch_attestation_bundle" do
    before do
      # Clean up any cached bundles
      bundle_cache_dir = HOMEBREW_CACHE/"attestation-bundles"
      FileUtils.rm_rf(bundle_cache_dir) if bundle_cache_dir.exist?
    end

    it "returns nil when bundle URL is not configured" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(nil)

      expect(described_class.fetch_attestation_bundle(fake_digest)).to be_nil
    end

    it "raises BundleFetchError for invalid digest" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_bundle_url_template)

      expect do
        described_class.fetch_attestation_bundle("invalid-digest")
      end.to raise_error(described_class::BundleFetchError, /Invalid sha256 digest format/)
    end

    it "raises BundleFetchError for digest that is too short" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_bundle_url_template)

      expect do
        described_class.fetch_attestation_bundle("abc123")
      end.to raise_error(described_class::BundleFetchError, /Invalid sha256 digest format/)
    end

    it "raises BundleFetchError for unsupported algorithm" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_bundle_url_template)

      expect do
        described_class.fetch_attestation_bundle(fake_digest, algorithm: :md5)
      end.to raise_error(described_class::BundleFetchError, /Unsupported digest algorithm/)
    end

    it "substitutes {hexdigest} with raw hex string in URL" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_bundle_url_template)

      expected_url = "https://mirror.internal/bundles/#{fake_digest}.jsonl"

      expect(Utils::Curl).to receive(:curl_download) do |url, to:, **_opts|
        expect(url).to eq expected_url
        to.write('{"attestation": "data"}')
      end

      result = described_class.fetch_attestation_bundle(fake_digest)
      expect(result).to be_a(Pathname)
      expect(result.basename.to_s).to eq "sha256_#{fake_digest}.jsonl"
    end

    it "substitutes {digest} with OCI-format (algorithm:hexdigest) in URL" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_oci_bundle_url_template)

      expected_url = "https://mirror.internal/bundles/sha256:#{fake_digest}.jsonl"

      expect(Utils::Curl).to receive(:curl_download) do |url, to:, **_opts|
        expect(url).to eq expected_url
        to.write('{"attestation": "data"}')
      end

      result = described_class.fetch_attestation_bundle(fake_digest)
      expect(result).to be_a(Pathname)
    end

    it "substitutes {algorithm} with algorithm name in URL" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return("https://mirror.internal/{algorithm}/{hexdigest}.jsonl")

      expected_url = "https://mirror.internal/sha256/#{fake_digest}.jsonl"

      expect(Utils::Curl).to receive(:curl_download) do |url, to:, **_opts|
        expect(url).to eq expected_url
        to.write('{"attestation": "data"}')
      end

      described_class.fetch_attestation_bundle(fake_digest)
    end

    it "uses filesystem-safe cache naming (algorithm_hexdigest)" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_oci_bundle_url_template)

      expect(Utils::Curl).to receive(:curl_download) do |_url, to:, **_opts|
        to.write('{"attestation": "data"}')
      end

      result = described_class.fetch_attestation_bundle(fake_digest)
      expect(result.basename.to_s).to eq "sha256_#{fake_digest}.jsonl"
    end

    it "uses cached bundle if within 24 hours" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_bundle_url_template)

      bundle_cache_dir = HOMEBREW_CACHE/"attestation-bundles"
      bundle_cache_dir.mkpath
      bundle_path = bundle_cache_dir/"sha256_#{fake_digest}.jsonl"
      bundle_path.write('{"cached": "bundle"}')

      # Should not call curl_download
      expect(Utils::Curl).not_to receive(:curl_download)

      result = described_class.fetch_attestation_bundle(fake_digest)
      expect(result).to eq bundle_path
    end

    it "re-fetches expired cache" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_bundle_url_template)

      bundle_cache_dir = HOMEBREW_CACHE/"attestation-bundles"
      bundle_cache_dir.mkpath
      bundle_path = bundle_cache_dir/"sha256_#{fake_digest}.jsonl"
      bundle_path.write('{"old": "bundle"}')
      # Set mtime to 25 hours ago (past the 24h cache duration)
      FileUtils.touch(bundle_path, mtime: Time.now - (25 * 3600))

      expect(Utils::Curl).to receive(:curl_download) do |_url, to:, **_opts|
        to.write('{"new": "bundle"}')
      end

      result = described_class.fetch_attestation_bundle(fake_digest)
      expect(result).to eq bundle_path
      expect(bundle_path.read).to eq '{"new": "bundle"}'
    end

    it "raises BundleFetchError on curl failure" do
      allow(Homebrew::EnvConfig).to receive(:attestation_bundle_url)
        .and_return(fake_bundle_url_template)

      expect(Utils::Curl).to receive(:curl_download)
        .and_raise(ErrorDuringExecution.new(["curl"], status: fake_curl_error_status))

      expect do
        described_class.fetch_attestation_bundle(fake_digest)
      end.to raise_error(described_class::BundleFetchError, /Failed to fetch attestation bundle/)
    end
  end

  describe "::trusted_root_path" do
    before do
      # Clean up cached trusted root
      cached_root = HOMEBREW_CACHE/"attestation-trusted-root.json"
      cached_root.unlink if cached_root.exist?
    end

    it "returns nil when not configured" do
      allow(Homebrew::EnvConfig).to receive(:attestation_trusted_root)
        .and_return(nil)

      expect(described_class.trusted_root_path).to be_nil
    end

    it "returns nil when configured as empty string" do
      allow(Homebrew::EnvConfig).to receive(:attestation_trusted_root)
        .and_return("")

      expect(described_class.trusted_root_path).to be_nil
    end

    it "returns local path when configured as file path" do
      Dir.mktmpdir do |dir|
        trusted_root_file = Pathname.new(dir)/"trusted_root.json"
        trusted_root_file.write('{"keys": []}')

        allow(Homebrew::EnvConfig).to receive(:attestation_trusted_root)
          .and_return(trusted_root_file.to_s)

        result = described_class.trusted_root_path
        expect(result).to eq trusted_root_file
      end
    end

    it "raises when local file doesn't exist" do
      allow(Homebrew::EnvConfig).to receive(:attestation_trusted_root)
        .and_return("/nonexistent/path/trusted_root.json")

      expect do
        described_class.trusted_root_path
      end.to raise_error(described_class::InvalidAttestationError, /Trusted root file not found/)
    end

    it "calls fetch_trusted_root_from_url when URL configured" do
      allow(Homebrew::EnvConfig).to receive(:attestation_trusted_root)
        .and_return(fake_trusted_root_url)

      fake_path = Pathname.new("/fake/cached/root.json")
      expect(described_class).to receive(:fetch_trusted_root_from_url)
        .with(fake_trusted_root_url)
        .and_return(fake_path)

      expect(described_class.trusted_root_path).to eq fake_path
    end
  end

  describe "::fetch_trusted_root_from_url" do
    let(:trusted_root_cache) { HOMEBREW_CACHE/"attestation-trusted-root.json" }

    before do
      trusted_root_cache.unlink if trusted_root_cache.exist?
    end

    it "fetches and caches trusted root" do
      expect(Utils::Curl).to receive(:curl_download) do |url, to:, **_opts|
        expect(url).to eq fake_trusted_root_url
        to.write('{"trusted": "root"}')
      end

      result = described_class.fetch_trusted_root_from_url(fake_trusted_root_url)
      expect(result).to eq trusted_root_cache
      expect(trusted_root_cache.read).to eq '{"trusted": "root"}'
    end

    it "uses fresh cache within 24 hours" do
      trusted_root_cache.dirname.mkpath
      trusted_root_cache.write('{"cached": "root"}')

      expect(Utils::Curl).not_to receive(:curl_download)

      result = described_class.fetch_trusted_root_from_url(fake_trusted_root_url)
      expect(result).to eq trusted_root_cache
    end

    it "re-fetches stale cache" do
      trusted_root_cache.dirname.mkpath
      trusted_root_cache.write('{"old": "root"}')
      FileUtils.touch(trusted_root_cache, mtime: Time.now - (25 * 3600))

      expect(Utils::Curl).to receive(:curl_download) do |_url, to:, **_opts|
        to.write('{"new": "root"}')
      end

      result = described_class.fetch_trusted_root_from_url(fake_trusted_root_url)
      expect(result).to eq trusted_root_cache
      expect(trusted_root_cache.read).to eq '{"new": "root"}'
    end

    context "when HOMEBREW_ATTESTATION_ALLOW_STALE_ROOT is set" do
      before do
        allow(Homebrew::EnvConfig).to receive(:attestation_allow_stale_root?)
          .and_return(true)
      end

      it "returns stale cache with warning when fetch fails" do
        trusted_root_cache.dirname.mkpath
        trusted_root_cache.write('{"stale": "root"}')
        FileUtils.touch(trusted_root_cache, mtime: Time.now - (25 * 3600))

        expect(Utils::Curl).to receive(:curl_download)
          .and_raise(ErrorDuringExecution.new(["curl"], status: fake_curl_error_status))

        expect(described_class).to receive(:opoo).twice

        result = described_class.fetch_trusted_root_from_url(fake_trusted_root_url)
        expect(result).to eq trusted_root_cache
      end
    end

    context "when HOMEBREW_ATTESTATION_ALLOW_STALE_ROOT is not set" do
      before do
        allow(Homebrew::EnvConfig).to receive(:attestation_allow_stale_root?)
          .and_return(false)
      end

      it "raises when stale and fetch fails" do
        trusted_root_cache.dirname.mkpath
        trusted_root_cache.write('{"stale": "root"}')
        FileUtils.touch(trusted_root_cache, mtime: Time.now - (25 * 3600))

        expect(Utils::Curl).to receive(:curl_download)
          .and_raise(ErrorDuringExecution.new(["curl"], status: fake_curl_error_status))

        expect do
          described_class.fetch_trusted_root_from_url(fake_trusted_root_url)
        end.to raise_error(described_class::InvalidAttestationError, /stale roots are not allowed/)
      end
    end

    it "raises when no cache and fetch fails" do
      expect(Utils::Curl).to receive(:curl_download)
        .and_raise(ErrorDuringExecution.new(["curl"], status: fake_curl_error_status))

      expect do
        described_class.fetch_trusted_root_from_url(fake_trusted_root_url)
      end.to raise_error(described_class::InvalidAttestationError, /Failed to fetch trusted root/)
    end
  end

  describe "BundleFetchError" do
    it "is a RuntimeError subclass" do
      expect(described_class::BundleFetchError.superclass).to eq RuntimeError
    end

    it "can be raised with a message" do
      expect do
        raise described_class::BundleFetchError, "test error message"
      end.to raise_error(described_class::BundleFetchError, "test error message")
    end
  end

  # NOTE: `Homebrew::CLI::NamedArgs` will often return frozen arrays of formulae
  #       so that's why we test with frozen arrays here.
  describe "::sort_formulae_for_install", :integration_test do
    let(:gh) { Formula["gh"] }
    let(:other) { Formula["other"] }

    before do
      setup_test_formula("gh")
      setup_test_formula("other")
    end

    context "when `gh` is in the formula list" do
      it "moves `gh` formulae to the front of the list" do
        expect(described_class).not_to receive(:gh_executable)

        [
          [[gh], [gh]],
          [[gh, other], [gh, other]],
          [[other, gh], [gh, other]],
        ].each do |input, output|
          expect(described_class.sort_formulae_for_install(input.freeze)).to eq(output)
        end
      end
    end

    context "when the formula list is empty" do
      it "checks for the `gh` executable" do
        expect(described_class).to receive(:gh_executable).once
        expect(described_class.sort_formulae_for_install([].freeze)).to eq([])
      end
    end

    context "when `gh` is not in the formula list" do
      it "checks for the `gh` executable" do
        expect(described_class).to receive(:gh_executable).once
        expect(described_class.sort_formulae_for_install([other].freeze)).to eq([other])
      end
    end
  end

  describe "::check_attestation" do
    before do
      allow(described_class).to receive(:gh_executable)
        .and_return(fake_gh)
    end

    it "raises without any gh credentials" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(nil)

      expect do
        described_class.check_attestation fake_bottle,
                                          described_class::HOMEBREW_CORE_REPO
      end.to raise_error(described_class::GhAuthNeeded)
    end

    it "raises when gh subprocess fails" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_raise(ErrorDuringExecution.new(["foo"], status: fake_error_status))

      expect do
        described_class.check_attestation fake_bottle,
                                          described_class::HOMEBREW_CORE_REPO
      end.to raise_error(described_class::InvalidAttestationError)
    end

    it "raises auth error when gh subprocess fails with auth exit code" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_raise(ErrorDuringExecution.new(["foo"], status: fake_auth_status))

      expect do
        described_class.check_attestation fake_bottle,
                                          described_class::HOMEBREW_CORE_REPO
      end.to raise_error(described_class::GhAuthInvalid)
    end

    it "raises when gh returns invalid JSON" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_invalid_json)

      expect do
        described_class.check_attestation fake_bottle,
                                          described_class::HOMEBREW_CORE_REPO
      end.to raise_error(described_class::InvalidAttestationError)
    end

    it "raises when gh returns other subjects" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_json_resp_wrong_sub)

      expect do
        described_class.check_attestation fake_bottle,
                                          described_class::HOMEBREW_CORE_REPO
      end.to raise_error(described_class::InvalidAttestationError)
    end

    it "checks subject prefix when the bottle is an :all bottle" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_json_resp)

      described_class.check_attestation fake_all_bottle, described_class::HOMEBREW_CORE_REPO
    end

    context "when offline_verification? is true" do
      let(:fake_bundle_path) { Pathname.new("/fake/bundle/path.jsonl") }
      let(:fake_root_path) { Pathname.new("/fake/trusted/root.json") }

      before do
        allow(described_class).to receive_messages(offline_verification?:    true,
                                                   fetch_attestation_bundle: fake_bundle_path,
                                                   trusted_root_path:        fake_root_path)
      end

      it "does not require GitHub credentials" do
        expect(GitHub::API).not_to receive(:credentials)

        expect(described_class).to receive(:system_command!)
          .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                                described_class::HOMEBREW_CORE_REPO, "--format", "json",
                                "--bundle", fake_bundle_path.to_s,
                                "--custom-trusted-root", fake_root_path.to_s],
                env: { "GH_HOST" => "github.com" }, secrets: [],
                print_stderr: false, chdir: HOMEBREW_TEMP)
          .and_return(fake_result_json_resp)

        described_class.check_attestation fake_bottle_with_resource, described_class::HOMEBREW_CORE_REPO
      end

      it "passes --bundle flag with bundle path" do
        expect(described_class).to receive(:system_command!) do |_gh, args:, **_opts|
          expect(args).to include("--bundle", fake_bundle_path.to_s)
        end.and_return(fake_result_json_resp)

        described_class.check_attestation fake_bottle_with_resource, described_class::HOMEBREW_CORE_REPO
      end

      it "passes --custom-trusted-root flag with root path" do
        expect(described_class).to receive(:system_command!) do |_gh, args:, **_opts|
          expect(args).to include("--custom-trusted-root", fake_root_path.to_s)
        end.and_return(fake_result_json_resp)

        described_class.check_attestation fake_bottle_with_resource, described_class::HOMEBREW_CORE_REPO
      end

      it "raises when bottle has no checksum" do
        fake_nil_checksum = instance_double(Checksum, hexdigest: nil)
        fake_nil_resource = instance_double(Resource, checksum: fake_nil_checksum)
        fake_bottle_no_checksum = instance_double(
          Bottle,
          cached_download:,
          filename:        fake_bottle_filename,
          url:             fake_bottle_url,
          tag:             fake_bottle_tag,
          resource:        fake_nil_resource,
        )

        expect do
          described_class.check_attestation fake_bottle_no_checksum, described_class::HOMEBREW_CORE_REPO
        end.to raise_error(described_class::InvalidAttestationError, /Bottle has no checksum/)
      end

      it "raises when trusted root not configured" do
        allow(described_class).to receive(:trusted_root_path)
          .and_return(nil)

        expect do
          described_class.check_attestation fake_bottle_with_resource, described_class::HOMEBREW_CORE_REPO
        end.to raise_error(described_class::InvalidAttestationError, /HOMEBREW_ATTESTATION_TRUSTED_ROOT must be set/)
      end

      it "raises InvalidAttestationError when bundle fetch fails" do
        allow(described_class).to receive(:fetch_attestation_bundle)
          .and_raise(described_class::BundleFetchError.new("fetch failed"))

        expect do
          described_class.check_attestation fake_bottle_with_resource, described_class::HOMEBREW_CORE_REPO
        end.to raise_error(described_class::InvalidAttestationError, /Offline verification failed/)
      end
    end
  end

  describe "::check_core_attestation" do
    before do
      allow(described_class).to receive(:gh_executable)
        .and_return(fake_gh)

      allow(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)
    end

    it "calls gh with args for homebrew-core" do
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_json_resp)

      described_class.check_core_attestation fake_bottle
    end

    it "calls gh with args for homebrew-core and handles a multi-subject attestation" do
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_json_resp_multi_subject)

      described_class.check_core_attestation fake_bottle
    end

    it "calls gh with args for backfill when homebrew-core attestation is missing" do
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .once
        .and_raise(described_class::MissingAttestationError)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::BACKFILL_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_json_resp_backfill)

      described_class.check_core_attestation fake_bottle
    end

    it "raises when the backfilled attestation is too new" do
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .exactly(described_class::ATTESTATION_MAX_RETRIES + 1)
        .and_raise(described_class::MissingAttestationError)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              described_class::BACKFILL_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .exactly(described_class::ATTESTATION_MAX_RETRIES + 1)
        .and_return(fake_result_json_resp_too_new)

      expect do
        described_class.check_core_attestation fake_bottle
      end.to raise_error(described_class::InvalidAttestationError)
    end
  end
end
