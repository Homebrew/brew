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
  let(:fake_bottle_resource) { instance_double(Resource, checksum: Checksum.new(fake_bottle_digest)) }
  let(:fake_bottle) do
    instance_double(Bottle, cached_download:, filename: fake_bottle_filename, url: fake_bottle_url,
                    tag: fake_bottle_tag, resource: fake_bottle_resource)
  end
  let(:fake_bundle) { { "mediaType" => "application/vnd.dev.sigstore.bundle.v0.3+json", "dsseEnvelope" => {} } }
  let(:fake_bundle_line) { JSON.generate(fake_bundle) }
  let(:fake_formula) { instance_double(Formula, bottle: fake_bottle, tap: instance_double(Tap, core_tap?: true)) }
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

  before { described_class.prefetched_bundles.clear }

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

  describe "::prefetch" do
    let(:bulk_list_url) { "https://api.github.com/orgs/Homebrew/attestations/bulk-list?per_page=100" }
    let(:backfill_bulk_list_url) { "https://api.github.com/orgs/trailofbits/attestations/bulk-list?per_page=100" }
    let(:listed_attestation) { { "bundle" => fake_bundle, "repository_id" => 1 } }
    let(:listed_digests) { { "sha256:#{fake_bottle_digest}" => [listed_attestation] } }
    let(:other_bottle_digest) { Digest::SHA256.hexdigest("other bottle") }
    let(:other_formula) do
      bottle = instance_double(Bottle,
                               resource: instance_double(Resource, checksum: Checksum.new(other_bottle_digest)))
      instance_double(Formula, bottle:, tap: instance_double(Tap, core_tap?: true))
    end

    before do
      ENV["HOMEBREW_VERIFY_ATTESTATIONS"] = "1"
      ENV.delete("HOMEBREW_NO_VERIFY_ATTESTATIONS")
      allow(GitHub::API).to receive(:credentials).and_return(fake_gh_creds)
    end

    it "lists the bottle digests from homebrew-core in one request" do
      expect(GitHub::API).to receive(:open_rest)
        .with(bulk_list_url, data: { subject_digests: ["sha256:#{fake_bottle_digest}"] }, request_method: :POST)
        .and_return("attestations_subject_digests" => listed_digests)

      described_class.prefetch([fake_formula])
    end

    it "records the listed bundles by digest and organisation" do
      allow(GitHub::API).to receive(:open_rest).and_return("attestations_subject_digests" => listed_digests)

      described_class.prefetch([fake_formula])

      expect(described_class.prefetched_bundles).to eq(fake_bottle_digest => { "Homebrew" => [fake_bundle_line] })
    end

    it "lists digests homebrew-core does not hold from the backfill organisation" do
      allow(GitHub::API).to receive(:open_rest)
        .with(bulk_list_url, any_args)
        .and_return("attestations_subject_digests" => {})
      allow(GitHub::API).to receive(:open_rest)
        .with(backfill_bulk_list_url, any_args)
        .and_return("attestations_subject_digests" => listed_digests)

      described_class.prefetch([fake_formula])

      expect(described_class.prefetched_bundles)
        .to eq(fake_bottle_digest => { "Homebrew" => [], "trailofbits" => [fake_bundle_line] })
    end

    it "records digests that neither organisation holds" do
      allow(GitHub::API).to receive(:open_rest).and_return("attestations_subject_digests" => {})

      described_class.prefetch([fake_formula])

      expect(described_class.prefetched_bundles)
        .to eq(fake_bottle_digest => { "Homebrew" => [], "trailofbits" => [] })
    end

    it "follows the listing's pagination" do
      first_page = {
        "attestations_subject_digests" => listed_digests,
        "page_info"                    => { "has_next" => true, "next" => "cursor" },
      }
      second_page = {
        "attestations_subject_digests" => { "sha256:#{other_bottle_digest}" => [listed_attestation] },
        "page_info"                    => { "has_next" => false },
      }
      allow(GitHub::API).to receive(:open_rest)
        .with(bulk_list_url, any_args)
        .and_return(first_page)
      allow(GitHub::API).to receive(:open_rest)
        .with("#{bulk_list_url}&after=cursor", any_args)
        .and_return(second_page)

      described_class.prefetch([fake_formula, other_formula])

      expect(described_class.prefetched_bundles.fetch(other_bottle_digest)).to eq("Homebrew" => [fake_bundle_line])
    end

    it "stops paginating when the listing names no next cursor" do
      page = { "attestations_subject_digests" => listed_digests, "page_info" => { "has_next" => true } }
      expect(GitHub::API).to receive(:open_rest).with(bulk_list_url, any_args).once.and_return(page)

      described_class.prefetch([fake_formula])
    end

    it "stops paginating when the next cursor does not advance" do
      page = {
        "attestations_subject_digests" => listed_digests,
        "page_info"                    => { "has_next" => true, "next" => "cursor" },
      }
      requested_urls = []
      allow(GitHub::API).to receive(:open_rest) do |url, **_options|
        requested_urls << url
        page
      end

      described_class.prefetch([fake_formula])

      expect(requested_urls).to eq([bulk_list_url, "#{bulk_list_url}&after=cursor"])
    end

    it "treats a listing without digests as empty" do
      allow(GitHub::API).to receive(:open_rest).and_return("attestations_subject_digests" => nil)

      expect { described_class.prefetch([fake_formula]) }.not_to raise_error
    end

    it "treats a null listing as empty" do
      allow(GitHub::API).to receive(:open_rest).and_return(nil)

      expect { described_class.prefetch([fake_formula]) }.not_to raise_error
    end

    it "skips digests that were already listed" do
      described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }
      expect(GitHub::API).not_to receive(:open_rest)

      described_class.prefetch([fake_formula])
    end

    it "ignores formulae from other taps" do
      formula = instance_double(Formula, bottle: fake_bottle, tap: instance_double(Tap, core_tap?: false))
      expect(GitHub::API).not_to receive(:open_rest)

      described_class.prefetch([formula])
    end

    it "does nothing unless attestations are verified" do
      ENV["HOMEBREW_NO_VERIFY_ATTESTATIONS"] = "1"
      expect(GitHub::API).not_to receive(:open_rest)

      described_class.prefetch([fake_formula])
    end

    it "does nothing without GitHub credentials" do
      allow(GitHub::API).to receive(:credentials).and_return(nil)
      expect(GitHub::API).not_to receive(:open_rest)

      described_class.prefetch([fake_formula])
    end

    it "leaves attestations without an inline bundle to be looked up online" do
      allow(GitHub::API).to receive(:open_rest).and_return(
        "attestations_subject_digests" => {
          "sha256:#{fake_bottle_digest}" => [{ "bundle_url" => "https://example.com/bundle", "repository_id" => 1 }],
        },
      )

      described_class.prefetch([fake_formula])

      expect(described_class.prefetched_bundles)
        .to eq(fake_bottle_digest => { "Homebrew" => [], "trailofbits" => [] })
    end

    it "does not raise when the listing fails" do
      allow(GitHub::API).to receive(:open_rest).and_raise(GitHub::API::HTTPNotFoundError, "Not Found")

      expect { described_class.prefetch([fake_formula]) }.not_to raise_error
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

    context "with listed attestations" do
      before do
        allow(GitHub::API).to receive(:credentials).and_return(fake_gh_creds)
      end

      it "verifies the bottle against its listed bundle" do
        described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }
        bundle_contents = []
        allow(described_class).to receive(:system_command!) do |_gh, args:, **_options|
          bundle_contents << Pathname(args.fetch(args.index("--bundle") + 1)).read
          fake_result_json_resp
        end

        described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO

        expect(bundle_contents).to eq(["#{fake_bundle_line}\n"])
      end

      it "removes the bundle file after verification" do
        described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }
        bundle_paths = []
        allow(described_class).to receive(:system_command!) do |_gh, args:, **_options|
          bundle_paths << args.fetch(args.index("--bundle") + 1)
          fake_result_json_resp
        end

        described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO

        expect(bundle_paths.fetch(0)).not_to exist
      end

      it "removes the bundle file when writing it fails" do
        described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }
        bundle_paths = []
        allow(Tempfile).to receive(:create).and_wrap_original do |create, *args|
          create.call(*args).tap do |file|
            bundle_paths << file.path
            allow(file).to receive(:puts).and_raise(Errno::ENOSPC)
          end
        end

        begin
          described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO
        rescue Errno::ENOSPC
          # The failed write is the point; the file must still be removed.
        end

        expect(Pathname(bundle_paths.fetch(0))).not_to exist
      end

      it "raises a missing attestation error when another organisation holds the attestations" do
        described_class.prefetched_bundles[fake_bottle_digest] =
          { "Homebrew" => [], "trailofbits" => [fake_bundle_line] }
        allow(described_class).to receive(:system_command!).and_return(fake_result_json_resp)

        expect do
          described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO
        end.to raise_error(Homebrew::Attestation::MissingAttestationError)
      end

      it "looks the attestation up online when no listed organisation holds it" do
        described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [], "trailofbits" => [] }
        expect(described_class).to receive(:system_command!)
          .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo",
                                Homebrew::Attestation::HOMEBREW_CORE_REPO, "--format", "json"],
                env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
                print_stderr: false, chdir: HOMEBREW_TEMP)
          .and_return(fake_result_json_resp)

        described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO
      end

      it "looks the attestation up online for an organisation that was not listed" do
        described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }
        expect(described_class).to receive(:system_command!)
          .with(fake_gh, args: ["attestation", "verify", cached_download, "--repo", "thirdparty/homebrew-tap",
                                "--format", "json"],
                env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
                print_stderr: false, chdir: HOMEBREW_TEMP)
          .and_return(fake_result_json_resp)

        described_class.check_attestation fake_bottle, "thirdparty/homebrew-tap"
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

    it "verifies a backfilled bottle without looking homebrew-core up online" do
      described_class.prefetched_bundles[fake_bottle_digest] =
        { "Homebrew" => [], "trailofbits" => [fake_bundle_line] }
      expect(described_class).to receive(:system_command!)
        .with(fake_gh, args: array_including("--repo", Homebrew::Attestation::BACKFILL_REPO, "--bundle"),
              env: { "GH_TOKEN" => fake_gh_creds, "GH_HOST" => "github.com" }, secrets: [fake_gh_creds],
              print_stderr: false, chdir: HOMEBREW_TEMP)
        .once
        .and_return(fake_result_json_resp_backfill)

      described_class.check_core_attestation fake_bottle
    end

    it "retries online after a listed bundle fails to verify" do
      described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }
      bundle_runs = []
      allow(described_class).to receive(:system_command!) do |_gh, args:, **_options|
        bundle_runs << args.include?("--bundle")
        raise ErrorDuringExecution.new([fake_gh.to_s], status: fake_error_status) if bundle_runs.length == 1

        fake_result_json_resp
      end

      described_class.check_core_attestation fake_bottle

      expect(bundle_runs).to eq([true, false])
    end

    it "retries online after a listed bundle fails validation" do
      described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }
      bundle_runs = []
      allow(described_class).to receive(:system_command!) do |_gh, args:, **_options|
        bundle_runs << args.include?("--bundle")
        (bundle_runs.length == 1) ? fake_json_resp_wrong_sub : fake_result_json_resp
      end

      described_class.check_core_attestation fake_bottle

      expect(bundle_runs).to eq([true, false])
    end
  end
end
