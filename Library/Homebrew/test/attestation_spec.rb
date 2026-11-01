# typed: true
# frozen_string_literal: true

require "diagnostic"
require "utils/attestation"

RSpec.describe Homebrew::Attestation do
  let(:fake_gh) { Pathname.new("/extremely/fake/gh") }
  let(:fake_gh_creds) { "fake-gh-api-token" }
  let(:fake_error_status) { instance_double(Process::Status, exitstatus: 1, termsig: nil) }
  let(:fake_auth_status) { instance_double(Process::Status, exitstatus: 4, termsig: nil) }
  let(:cached_download) { (mktmpdir/"bottle.tar.gz").tap { |path| path.write("bottle") } }
  let(:fake_bottle_digest) { Digest::SHA256.hexdigest("bottle") }
  let(:fake_subject) { { name: fake_bottle_filename.to_s, digest: { sha256: fake_bottle_digest } } }
  let(:fake_bottle_filename) do
    instance_double(Bottle::Filename, name: "fakebottle", version: "1.0",
   to_s: "fakebottle--1.0.faketag.bottle.tar.gz")
  end
  let(:fake_bottle_url) { "https://example.com/#{fake_bottle_filename}" }
  let(:fake_bottle_tag) { instance_double(Utils::Bottles::Tag, to_sym: :faketag) }
  let(:fake_all_bottle_tag) { instance_double(Utils::Bottles::Tag, to_sym: :all) }
  let(:fake_bottle) do
    instance_double(Bottle, cached_download:, filename: fake_bottle_filename, url: fake_bottle_url,
                    tag: fake_bottle_tag)
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
                        statement:          { subject: [fake_subject] },
                      } },
                    ]))
  end
  let(:fake_result_json_resp_multi_subject) do
    instance_double(SystemCommand::Result,
                    stdout: JSON.dump([
                      { verificationResult: {
                        verifiedTimestamps: [{ timestamp: "2024-03-13T00:00:00Z" }],
                        statement:          { subject: [{ name: "nonsense" }, fake_subject] },
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
                          subject: [fake_subject.merge(name: "#{digest}--#{fake_bottle_filename}")],
                        },
                      } },
                    ]))
  end
  let(:fake_result_json_resp_too_new) do
    instance_double(SystemCommand::Result,
                    stdout: JSON.dump([
                      { verificationResult: {
                        verifiedTimestamps: [{ timestamp: "2024-03-15T00:00:00Z" }],
                        statement:          { subject: [fake_subject] },
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
      expect(Utils::Executable).to receive(:ensure!)
        .with("gh", reason: "verifying attestations", latest: true)
        .and_return(fake_gh)

      described_class.gh_executable
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
                                          Homebrew::Attestation::HOMEBREW_CORE_REPO
      end.to raise_error(Homebrew::Attestation::GhAuthNeeded)
    end

    it "raises when gh subprocess fails" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_raise(ErrorDuringExecution.new(["foo"], status: fake_error_status))

      expect do
        described_class.check_attestation fake_bottle,
                                          Homebrew::Attestation::HOMEBREW_CORE_REPO
      end.to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    test_each(["HTTP 403: Forbidden", "HTTP 429: Too Many Requests", "HTTP 500: API rate limit exceeded"]) do |stderr|
      it "does not classify #{stderr} as an API rate limit" do
        allow(GitHub::API).to receive(:credentials).and_return(fake_gh_creds)
        allow(described_class).to receive(:system_command!)
          .and_raise(ErrorDuringExecution.new([fake_gh.to_s], status: fake_error_status, output: [[:stderr, stderr]]))

        expect do
          described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO
        end.to raise_error(Homebrew::Attestation::InvalidAttestationError)
      end
    end

    it "classifies a secondary rate limit as an API rate limit" do
      stderr = "HTTP 403: You have exceeded a secondary rate limit."
      allow(GitHub::API).to receive(:credentials).and_return(fake_gh_creds)
      allow(described_class).to receive(:system_command!)
        .and_raise(ErrorDuringExecution.new([fake_gh.to_s], status: fake_error_status, output: [[:stderr, stderr]]))

      expect do
        described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO
      end.to raise_error(Homebrew::Attestation::RateLimitExceededError)
    end

    it "raises auth error when gh subprocess fails with auth exit code" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_raise(ErrorDuringExecution.new(["foo"], status: fake_auth_status))

      expect do
        described_class.check_attestation fake_bottle,
                                          Homebrew::Attestation::HOMEBREW_CORE_REPO
      end.to raise_error(Homebrew::Attestation::GhAuthInvalid)
    end

    it "raises when gh returns invalid JSON" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_invalid_json)

      expect do
        described_class.check_attestation fake_bottle,
                                          Homebrew::Attestation::HOMEBREW_CORE_REPO
      end.to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    it "raises when gh returns other subjects" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_json_resp_wrong_sub)

      expect do
        described_class.check_attestation fake_bottle,
                                          Homebrew::Attestation::HOMEBREW_CORE_REPO
      end.to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    it "checks subject prefix when the bottle is an :all bottle" do
      expect(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_json_resp)

      described_class.check_attestation fake_all_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO
    end

    context "when the subject name and digest match different artifacts" do
      let(:fake_subject) do
        { name: fake_bottle_filename.to_s, digest: { sha256: Digest::SHA256.hexdigest("other bottle") } }
      end

      before do
        response = JSON.parse(fake_result_json_resp.stdout)
        response.first.fetch("verificationResult").fetch("statement").fetch("subject") <<
          { name: "other-bottle.tar.gz", digest: { sha256: fake_bottle_digest } }
        allow(GitHub::API).to receive(:credentials).and_return(fake_gh_creds)
        allow(described_class).to receive(:system_command!)
          .and_return(instance_double(SystemCommand::Result, stdout: JSON.generate(response)))
      end

      it "rejects the attestation" do
        expect do
          described_class.check_attestation(fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO)
        end.to raise_error(Homebrew::Attestation::InvalidAttestationError, /no attestation matches subject/)
      end

      it "rejects the attestation for an :all bottle" do
        expect do
          described_class.check_attestation(fake_all_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO)
        end.to raise_error(Homebrew::Attestation::InvalidAttestationError, /no attestation matches subject/)
      end
    end

    context "when an :all bottle's version is a prefix of another version" do
      before do
        allow(GitHub::API).to receive(:credentials).and_return(fake_gh_creds)
        allow(described_class).to receive(:system_command!) { fake_result_json_resp }
      end

      it "rejects an attestation for a different version" do
        fake_subject[:name] = "fakebottle--1.0.1.faketag.bottle.tar.gz"

        expect do
          described_class.check_attestation(fake_all_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO)
        end.to raise_error(Homebrew::Attestation::InvalidAttestationError, /no attestation matches subject/)
      end
    end
  end

  describe "::check_formula_attestation" do
    let(:bottle_resource) { instance_double(Resource, owner: formula_owner) }
    let(:attested_bottle) { instance_double(Bottle, resource: bottle_resource) }
    let(:formula_owner) do
      formula("fformula-name", tap: Tap.fetch("thirdparty", "tap")) do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/fformula-name-1.0.tar.gz"
      end
    end

    it "uses the tap repository for supported third-party taps" do
      expect(described_class).to receive(:check_attestation)
        .with(attested_bottle, "thirdparty/homebrew-tap")
        .and_return({})

      described_class.check_formula_attestation(attested_bottle)
    end

    it "routes homebrew/core bottles through the core verifier" do
      core_formula = formula("core-attested") do
        T.bind(self, T.class_of(Formula))
        url "https://brew.sh/core-attested-1.0.tar.gz"
      end
      core_bottle = instance_double(Bottle, resource: instance_double(Resource, owner: core_formula))

      expect(described_class).to receive(:check_core_attestation)
        .with(core_bottle)
        .and_return({})

      described_class.check_formula_attestation(core_bottle)
    end

    it "raises for third-party taps with custom remotes" do
      custom_tap = instance_double(
        Tap,
        core_tap?:      false,
        official?:      false,
        custom_remote?: true,
        name:           "thirdparty/tap",
      )
      allow(formula_owner).to receive(:tap).and_return(custom_tap)

      expect do
        described_class.check_formula_attestation(attested_bottle)
      end.to raise_error(Homebrew::Attestation::UnsupportedTapError, /non-default remote/)
    end
  end

  describe "::check_core_attestation" do
    before do
      allow(described_class).to receive(:gh_executable)
        .and_return(fake_gh)

      allow(GitHub::API).to receive(:credentials)
        .and_return(fake_gh_creds)
    end

    test_each([403, 429]) do |status|
      context "when gh returns HTTP #{status}: API rate limit exceeded" do
        let(:rate_limit_error) do
          ErrorDuringExecution.new(
            [fake_gh.to_s], status: fake_error_status,
                            output: [[:stderr, "HTTP #{status}: API rate limit exceeded"]]
          )
        end

        before do
          allow(described_class).to receive(:system_command!).and_raise(rate_limit_error)
        end

        it "raises a distinct rate-limit error" do
          expect do
            described_class.check_core_attestation fake_bottle
          end.to raise_error(Homebrew::Attestation::RateLimitExceededError)
        end

        it "does not retry the lookup" do
          expect(described_class).to receive(:system_command!).once.and_raise(rate_limit_error)

          begin
            described_class.check_core_attestation fake_bottle
          rescue RuntimeError
            nil
          end
        end

        it "fails installation with a rate-limit message" do
          allow(fake_bottle).to receive(:name).and_return("fakebottle")
          allow(described_class).to receive(:check_formula_attestation) do
            described_class.check_core_attestation fake_bottle
          end

          expect do
            Utils::Attestation.check_attestation(fake_bottle, quiet: true)
          end.to raise_error(CannotInstallFormulaError, <<~EOS)
            The bottle for fakebottle could not be verified.

            Attestation verification could not complete because the GitHub API rate
            limit was exceeded. Please try again later.
          EOS
        end

        it "does not retry a rate-limited backfill lookup" do
          allow(described_class).to receive(:check_attestation)
            .with(fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO)
            .and_raise(Homebrew::Attestation::MissingAttestationError)
          allow(described_class).to receive(:check_attestation).with(fake_bottle,
                                                                     Homebrew::Attestation::BACKFILL_REPO,
                                                                     any_args).and_call_original

          expect(described_class).to receive(:system_command!).once.and_raise(rate_limit_error)

          begin
            described_class.check_core_attestation fake_bottle
          rescue RuntimeError
            nil
          end
        end
      end
    end

    it "calls gh with args for homebrew-core" do
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_json_resp)

      described_class.check_core_attestation fake_bottle
    end

    it "calls gh with args for homebrew-core and handles a multi-subject attestation" do
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_json_resp_multi_subject)

      described_class.check_core_attestation fake_bottle
    end

    it "calls gh with args for backfill when homebrew-core attestation is missing" do
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .once
        .and_raise(Homebrew::Attestation::MissingAttestationError)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::BACKFILL_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .and_return(fake_result_json_resp_backfill)

      described_class.check_core_attestation fake_bottle
    end

    it "raises when the backfilled attestation is too new" do
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .exactly(Homebrew::Attestation::ATTESTATION_MAX_RETRIES + 1)
        .and_raise(Homebrew::Attestation::MissingAttestationError)

      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                              Homebrew::Attestation::BACKFILL_REPO, "--format", "json"],
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .exactly(Homebrew::Attestation::ATTESTATION_MAX_RETRIES + 1)
        .and_return(fake_result_json_resp_too_new)

      expect do
        described_class.check_core_attestation fake_bottle
      end.to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end
  end
end
