# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Attestation do
  let(:fake_gh) { Pathname.new("/extremely/fake/gh") }
  let(:fake_old_gh) { Pathname.new("/extremely/fake/old/gh") }
  let(:fake_gh_creds) { "fake-gh-api-token" }
  let(:fake_error_status) { instance_double(Process::Status, exitstatus: 1, termsig: nil) }
  let(:fake_auth_status) { instance_double(Process::Status, exitstatus: 4, termsig: nil) }
  let(:cached_download) { "/fake/cached/download" }
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
