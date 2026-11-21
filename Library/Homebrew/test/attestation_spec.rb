# typed: true
# frozen_string_literal: true

require "diagnostic"
require "utils/attestation"

RSpec.describe Homebrew::Attestation do
  let(:fake_gh) { Pathname.new("/extremely/fake/gh") }
  let(:fake_gh_creds) { "fake-gh-api-token" }
  let(:fake_error_status) { instance_double(Process::Status, exitstatus: 1, termsig: nil) }
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
                    tag: fake_all_bottle_tag, resource: fake_bottle_resource)
  end
  let(:fake_result_json_resp) do
    instance_double(SystemCommand::Result,
                    stdout: JSON.dump([
                      { verificationResult: {
                        verifiedTimestamps: [{ timestamp: "2024-03-13T00:00:00Z" }],
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

  # A bottle that the real `publish-commit-bottles.yml` bundle attests, listed for homebrew-core.
  shared_context "with a listed homebrew-core bundle" do
    let(:fake_bottle_digest) { "6647e78fa0031ae48458496a4c46dee645fa8f8dda44d35f3a095627590e77b1" }
    let(:fake_bottle_filename) do
      instance_double(Bottle::Filename, name: "gmp", version: "6.3.0",
                                       to_s: "gmp--6.3.0.arm64_linux.bottle.1.tar.gz")
    end
    let(:listed_bundle) { (TEST_FIXTURE_DIR/"attestation/publish-commit-bottles.json").read }

    before do
      allow(Downloadable.verification_cache).to receive(:sha256).and_return(fake_bottle_digest)
      described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [listed_bundle] }
    end
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

  describe "::prefetch" do
    let(:bulk_list_url) { "https://api.github.com/orgs/Homebrew/attestations/bulk-list?per_page=100" }
    let(:backfill_bulk_list_url) { "https://api.github.com/orgs/trailofbits/attestations/bulk-list?per_page=100" }
    let(:listed_attestation) { { "bundle" => fake_bundle, "repository_id" => 1 } }
    let(:url_only_attestation) { { "bundle_url" => "https://example.com/bundle", "repository_id" => 1 } }
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

    it "leaves a digest held only as bundle_url attestations to the online lookup" do
      requested_urls = []
      allow(GitHub::API).to receive(:open_rest) do |url, **_options|
        requested_urls << url
        {
          "attestations_subject_digests" => {
            "sha256:#{fake_bottle_digest}"  => [listed_attestation],
            "sha256:#{other_bottle_digest}" => [url_only_attestation],
          },
        }
      end

      described_class.prefetch([fake_formula, other_formula])

      expect([requested_urls, described_class.prefetched_bundles])
        .to eq([[bulk_list_url], { fake_bottle_digest => { "Homebrew" => [fake_bundle_line] } }])
    end

    it "treats a digest listed without attestations as not held" do
      allow(GitHub::API).to receive(:open_rest)
        .and_return("attestations_subject_digests" => { "sha256:#{fake_bottle_digest}" => [] })

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
    let(:fake_result_invalid_json) { instance_double(SystemCommand::Result, stdout: "\"invalid JSON") }

    let(:fake_auth_status) { instance_double(Process::Status, exitstatus: 4, termsig: nil) }

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

      it "rejects listed bundles that do not verify" do
        described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }

        expect do
          described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO
        end.to raise_error(Homebrew::Attestation::InvalidAttestationError, /unsupported bundle form/)
      end

      context "with a real bundle" do
        include_context "with a listed homebrew-core bundle"

        before { allow(described_class).to receive(:system_command!).and_raise("verification ran `gh`") }

        it "verifies the bottle against its listed bundle without `gh`" do
          expect(described_class.check_attestation(fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO)
                                .dig("verificationResult", "verifiedTimestamps"))
            .to eq([{ "timestamp" => "2026-09-02T14:33:41Z" }])
        end

        it "accepts the valid bundle among several listed" do
          described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line, listed_bundle] }

          expect { described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO }
            .not_to raise_error
        end

        test_each_hash({
          "another platform"         => "gmp--6.3.0.arm64_tahoe.bottle.1.tar.gz",
          "an older version"         => "gmp--6.2.1.arm64_linux.bottle.1.tar.gz",
          "another rebuild"          => "gmp--6.3.0.arm64_linux.bottle.tar.gz",
          "another formula's bottle" => "hello--2.12.3.arm64_linux.bottle.1.tar.gz",
        }) do |bottle, filename|
          it "rejects a listed bundle whose digest is signed for #{bottle}" do
            allow(fake_bottle_filename).to receive(:to_s).and_return(filename)

            expect { described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO }
              .to raise_error(Homebrew::Attestation::InvalidAttestationError, /no attestation matches subject/)
          end
        end

        it "rejects a bottle that does not match its formula checksum" do
          allow(fake_bottle_resource).to receive(:checksum).and_return(Checksum.new("0" * 64))

          expect { described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO }
            .to raise_error(Homebrew::Attestation::InvalidAttestationError, /formula checksum/)
        end

        it "rejects a listed bundle under another repository's policy" do
          described_class.prefetched_bundles[fake_bottle_digest] = { "trailofbits" => [listed_bundle] }

          expect { described_class.check_attestation fake_bottle, Homebrew::Attestation::BACKFILL_REPO }
            .to raise_error(Homebrew::Attestation::InvalidAttestationError, /source repository does not match/)
        end

        context "with an :all bottle" do
          let(:fake_bottle_tag) { fake_all_bottle_tag }

          it "accepts any tag of the same name and version" do
            allow(fake_bottle_filename).to receive(:to_s).and_return("gmp--6.3.0.all.bottle.1.tar.gz")

            expect { described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO }
              .not_to raise_error
          end

          it "rejects another version" do
            allow(fake_bottle_filename).to receive(:version).and_return("6.3.1")

            expect { described_class.check_attestation fake_bottle, Homebrew::Attestation::HOMEBREW_CORE_REPO }
              .to raise_error(Homebrew::Attestation::InvalidAttestationError, /no attestation matches subject/)
          end
        end
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
    let(:fake_result_json_resp_too_new) do
      instance_double(SystemCommand::Result,
                      stdout: JSON.dump([
                        { verificationResult: {
                          verifiedTimestamps: [{ timestamp: "2024-03-15T00:00:00Z" }],
                          statement:          { subject: [fake_subject] },
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

    let(:fake_result_json_resp_multi_subject) do
      instance_double(SystemCommand::Result,
                      stdout: JSON.dump([
                        { verificationResult: {
                          verifiedTimestamps: [{ timestamp: "2024-03-13T00:00:00Z" }],
                          statement:          { subject: [{ name: "nonsense" }, fake_subject] },
                        } },
                      ]))
    end

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

            To skip attestation verification, set `HOMEBREW_NO_VERIFY_ATTESTATIONS=1`.
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

    context "with a backfilled :all bottle" do
      let(:fake_bottle_tag) { fake_all_bottle_tag }
      let(:fake_bottle_filename) do
        instance_double(Bottle::Filename, name: "fakebottle", version: "1.0",
                                         to_s: "fakebottle--1.0.all.bottle.tar.gz")
      end

      before do
        allow(described_class).to receive(:system_command!) do |_gh, args:, **_options|
          unless args.include?(Homebrew::Attestation::BACKFILL_REPO)
            raise Homebrew::Attestation::MissingAttestationError
          end

          fake_result_json_resp_backfill
        end
      end

      it "verifies the URL-prefixed subject" do
        expect(described_class.check_core_attestation(fake_bottle))
          .to eq(JSON.parse(fake_result_json_resp_backfill.stdout).first)
      end

      it "rejects an attestation for a different URL" do
        allow(fake_bottle).to receive(:url).and_return("https://example.org/#{fake_bottle_filename}")

        expect do
          described_class.check_core_attestation(fake_bottle)
        end.to raise_error(Homebrew::Attestation::InvalidAttestationError, /no attestation matches subject/)
      end

      it "rejects an attestation for a different digest" do
        fake_subject[:digest][:sha256] = Digest::SHA256.hexdigest("other bottle")

        expect do
          described_class.check_core_attestation(fake_bottle)
        end.to raise_error(Homebrew::Attestation::InvalidAttestationError, /no attestation matches subject/)
      end

      context "without a URL hash prefix" do
        let(:fake_result_json_resp_backfill) { fake_result_json_resp }

        it "rejects the attestation" do
          expect do
            described_class.check_core_attestation(fake_bottle)
          end.to raise_error(Homebrew::Attestation::InvalidAttestationError, /no attestation matches subject/)
        end
      end
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

    context "with a listed backfill bundle" do
      let(:fake_bottle_digest) { "0ebfa147cd1a513a86323167ab696a94b490dcd215d6685188bc376bf1313953" }
      let(:fake_bottle_url) { "https://ghcr.io/v2/homebrew/core/figlet/blobs/sha256:#{fake_bottle_digest}" }
      let(:fake_bottle_filename) do
        instance_double(Bottle::Filename, name: "figlet", version: "2.2.5",
                                         to_s: "figlet--2.2.5.arm64_ventura.bottle.tar.gz")
      end

      before do
        allow(Downloadable.verification_cache).to receive(:sha256).and_return(fake_bottle_digest)
        described_class.prefetched_bundles[fake_bottle_digest] =
          { "Homebrew" => [], "trailofbits" => [(TEST_FIXTURE_DIR/"attestation/backfill.json").read] }
      end

      it "verifies the bottle without `gh`" do
        expect(described_class).not_to receive(:system_command!)

        described_class.check_core_attestation fake_bottle
      end

      it "rejects a bundle for a different URL" do
        allow(fake_bottle).to receive(:url).and_return("https://example.org/#{fake_bottle_filename}")
        allow(described_class).to receive(:system_command!).and_raise(Homebrew::Attestation::MissingAttestationError)

        # The retry looks both repositories up online, where the stub holds no attestation.
        expect { described_class.check_core_attestation fake_bottle }
          .to raise_error(Homebrew::Attestation::MissingAttestationError)
      end
    end

    it "retries online after a listed bundle fails to verify" do
      described_class.prefetched_bundles[fake_bottle_digest] = { "Homebrew" => [fake_bundle_line] }
      expect(described_class).to receive(:system_command!).once.and_return(fake_result_json_resp)

      described_class.check_core_attestation fake_bottle
    end

    context "with a listed bundle for another platform" do
      include_context "with a listed homebrew-core bundle"

      it "retries online" do
        allow(fake_bottle_filename).to receive(:to_s).and_return("gmp--6.3.0.arm64_tahoe.bottle.1.tar.gz")
        expect(described_class).to receive(:system_command!).once.and_return(fake_result_json_resp)

        described_class.check_core_attestation fake_bottle
      end
    end
  end

  describe "::verify_bundle" do
    let(:digest) { "6647e78fa0031ae48458496a4c46dee645fa8f8dda44d35f3a095627590e77b1" }
    let(:bundle) { JSON.parse((TEST_FIXTURE_DIR/"attestation/publish-commit-bottles.json").read) }

    def signing_repo = Homebrew::Attestation::HOMEBREW_CORE_REPO

    # The bottle digests attested by the named fixture: a real bundle from that signer.
    def verified_digests(fixture, digest, signing_repo)
      described_class.verify_bundle((TEST_FIXTURE_DIR/"attestation/#{fixture}.json").read, digest, signing_repo)
                     .dig("verificationResult", "statement", "subject")
                     .map { |subject| subject.dig("digest", "sha256") }
    end

    def envelope_signature(bundle) = bundle.fetch("dsseEnvelope").fetch("signatures").fetch(0)

    def log_entry(bundle) = bundle.fetch("verificationMaterial").fetch("tlogEntries").fetch(0)

    # Swaps the case of one letter of a Base64 string: still valid Base64 for different bytes.
    def corrupt(base64) = base64.sub(/[a-z]/i, &:swapcase)

    def corrupt_signature(base64)
      bytes = base64.unpack1("m0")
      bytes.setbyte(-1, bytes.bytes.fetch(-1) ^ 1)
      [bytes].pack("m0")
    end

    before do
      # Verification must never make a request.
      [[TCPSocket, :new], [TCPSocket, :open], [Socket, :tcp]].each do |socket_class, method|
        allow(socket_class).to receive(method).and_raise("verification attempted a network connection")
      end
    end

    it "verifies a publish-commit-bottles bundle" do
      expect(verified_digests("publish-commit-bottles", digest, signing_repo)).to include(digest)
    end

    it "verifies a dispatch-build-bottle bundle" do
      digest = "08cea07f0d5aa44680d79cf97dbae12da8f80e85deb70b36f0e701be0896efd5"

      expect(verified_digests("dispatch-build-bottle", digest, signing_repo)).to include(digest)
    end

    it "verifies a dispatch-rebottle bundle" do
      digest = "d3a17c017f2a07e9b1fcdbb28a13bcb77a832a13ca822c526ed3d950b579cd41"

      expect(verified_digests("dispatch-rebottle", digest, signing_repo)).to include(digest)
    end

    it "verifies a backfill bundle" do
      digest = "0ebfa147cd1a513a86323167ab696a94b490dcd215d6685188bc376bf1313953"

      expect(verified_digests("backfill", digest, Homebrew::Attestation::BACKFILL_REPO)).to include(digest)
    end

    it "verifies a bundle signed from `master` before homebrew-core's default branch was renamed" do
      digest = "345e99255a69e9cb188a5a8e6bd8e6f50c334830c8a72877fc6b504c95e5cbd1"

      expect(verified_digests("publish-commit-bottles-master", digest, signing_repo)).to include(digest)
    end

    it "verifies a backfill bundle signed from the `backfill` branch" do
      digest = "6ba926f8aadec9e5c30880ae6e6497d44f9045d1ca1f680baf28e67309bd8ecd"

      expect(verified_digests("backfill-branch", digest, Homebrew::Attestation::BACKFILL_REPO)).to include(digest)
    end

    it "accepts an uppercase expected SHA-256" do
      expect(verified_digests("publish-commit-bottles", digest.upcase, signing_repo)).to include(digest)
    end

    it "returns the time the transparency log recorded the signature" do
      result = described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo)

      expect(result.dig("verificationResult", "verifiedTimestamps"))
        .to eq([{ "timestamp" => "2026-09-02T14:33:41Z" }])
    end

    it "rejects a bundle for another bottle" do
      expect { described_class.verify_bundle(JSON.generate(bundle), "0" * 64, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError, /None of in-toto subjects matches/)
    end

    it "rejects a repository without a trust policy" do
      expect { described_class.verify_bundle(JSON.generate(bundle), digest, "thirdparty/homebrew-tap") }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError, /no trust policy/)
    end

    it "rejects a tampered statement" do
      envelope = bundle.fetch("dsseEnvelope")
      envelope["payload"] = [envelope.fetch("payload").unpack1("m").sub("gmp--6.3.0", "gmp--6.3.1")].pack("m0")

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    it "rejects a tampered signature" do
      envelope_signature(bundle)["sig"] = corrupt(envelope_signature(bundle).fetch("sig"))

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    it "rejects a tampered certificate" do
      certificate = bundle.fetch("verificationMaterial").fetch("certificate")
      certificate["rawBytes"] = corrupt(certificate.fetch("rawBytes").reverse).reverse

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    it "rejects a tampered log time without quoting signature bytes" do
      log_entry(bundle)["integratedTime"] = (log_entry(bundle).fetch("integratedTime").to_i + 1).to_s

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError,
                        "attestation verification failed: invalid inclusion promise")
    end

    it "rejects whitespace in the signed log time" do
      integrated_time = log_entry(bundle).fetch("integratedTime")
      log_entry(bundle)["integratedTime"] = " #{integrated_time}"

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    it "rejects a log time that the log has not signed" do
      log_entry(bundle).delete("inclusionPromise")
      log_entry(bundle)["integratedTime"] = (log_entry(bundle).fetch("integratedTime").to_i + 1).to_s

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError, /unsupported bundle form/)
    end

    it "rejects a field under the other name protobuf reads it by" do
      bundle["dsse_envelope"] = bundle.delete("dsseEnvelope")

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError, /unsupported bundle form/)
    end

    it "rejects a tampered log inclusion proof" do
      hashes = log_entry(bundle).fetch("inclusionProof").fetch("hashes")
      hashes[0] = corrupt(hashes.fetch(0))

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    it "rejects a log entry for another signature" do
      log_entry(bundle)["canonicalizedBody"] = ['{"apiVersion":"0.0.1","kind":"dsse","spec":{}}'].pack("m0")

      expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    it "rejects malformed JSON" do
      expect { described_class.verify_bundle("{", digest, signing_repo) }
        .to raise_error(Homebrew::Attestation::InvalidAttestationError)
    end

    test_each(%w[2.13.0 2.14.0 2.18.0 2.19.0 2.19.1 2.19.2.pre]) do |json_version|
      it "refuses JSON #{json_version} before parsing untrusted input" do
        stub_const("JSON::VERSION", json_version)
        allow(JSON).to receive(:parse).and_raise("untrusted input reached the parser")

        expect { described_class.verify_bundle('{"%%":1,"%%":2}', digest, signing_repo) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /requires JSON >= 2\.19\.2/)
      end
    end

    test_each(%w[2.19.2 2.20.0 3.0.0 3.1.0]) do |json_version|
      it "allows verification with JSON #{json_version}" do
        stub_const("JSON::VERSION", json_version)

        expect(verified_digests("publish-commit-bottles", digest, signing_repo)).to include(digest)
      end
    end

    it "reports unexpected exceptions by class without their message" do
      require "attestation/verifier"
      allow(Homebrew::Attestation::Verifier).to receive(:verify).and_raise(ArgumentError, "signature bytes")
      error = begin
        described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo)
      rescue Homebrew::Attestation::InvalidAttestationError => e
        e
      end

      expect(error).to have_attributes(
        message: "attestation verification failed: ArgumentError",
        cause:   nil,
      )
    end

    context "with individual verification checks" do
      let(:verifier) { Homebrew::Attestation::Verifier }
      let(:entry) { verifier.parse_bundle(JSON.generate(bundle)).log_entry }
      let(:leaf) do
        OpenSSL::X509::Certificate.new(
          bundle.fetch("verificationMaterial").fetch("certificate").fetch("rawBytes").unpack1("m0"),
        )
      end
      let(:issuer) { verifier.verify_certificate(leaf, time).fetch(1) }
      let(:policy) { Homebrew::Attestation::Verifier::POLICIES.fetch(0) }

      def proof = entry.inclusion_proof
      def body = entry.body
      def payload = bundle.fetch("dsseEnvelope").fetch("payload").unpack1("m0")
      def signature = envelope_signature(bundle).fetch("sig").unpack1("m0")
      def time = Time.at(entry.integrated_time).utc
      def key_id = entry.log_id
      def key = verifier.trusted_key(verifier.trusted_root.transparency_logs, key_id, time)

      before { require "attestation/verifier" }

      context "when JSON permits duplicate keys by default" do
        before do
          allow(JSON).to receive(:parse).and_wrap_original do |parse, source, **options|
            parse.call(source, allow_duplicate_key: true, **options)
          end
        end

        test_each(%w[mediaType integratedTime]) do |field|
          it "rejects a duplicate #{field} in the bundle" do
            duplicate = JSON.generate(bundle).sub(%Q("#{field}":), %Q("#{field}":null,"#{field}":))

            expect { described_class.verify_bundle(duplicate, digest, signing_repo) }
              .to raise_error(Homebrew::Attestation::InvalidAttestationError,
                              "attestation verification failed: JSON::ParserError")
          end
        end

        it "rejects a duplicate key with another JSON escape spelling" do
          duplicate = JSON.generate(bundle).sub('"mediaType":', '"media\\u0054ype":null,"mediaType":')

          expect { described_class.verify_bundle(duplicate, digest, signing_repo) }
            .to raise_error(Homebrew::Attestation::InvalidAttestationError,
                            "attestation verification failed: JSON::ParserError")
        end

        it "rejects duplicate keys in the trusted root" do
          duplicate = (HOMEBREW_LIBRARY_PATH/"attestation/trusted_root.json").read.insert(1, '"tlogs":null,')

          expect { verifier.parse_trusted_root(duplicate) }.to raise_error(JSON::ParserError)
        end

        it "rejects duplicate keys in the log body" do
          expect { verifier.verify_body(body.dup.insert(1, '"kind":null,'), payload, signature, leaf) }
            .to raise_error(JSON::ParserError)
        end

        it "rejects duplicate keys in the statement" do
          expect { verifier.verify_statement(payload.dup.insert(1, '"_type":null,'), digest) }
            .to raise_error(JSON::ParserError)
        end

        it "treats percent signs in duplicate keys as literal text" do
          expect { verifier.parse_bundle('{"%%":1,"%%":2}') }
            .to raise_error(JSON::ParserError, /duplicate key "%%"/)
        end
      end

      test_each(%w[promise checkpoint ca missing_sct altered_sct altered_dsse log_payload log_signature
                   log_certificate statement_type]) do |tamper|
        it "rejects a bundle with #{tamper.tr("_", " ")}" do
          case tamper
          when "promise"
            promise = log_entry(bundle).fetch("inclusionPromise")
            promise["signedEntryTimestamp"] = corrupt_signature(promise.fetch("signedEntryTimestamp"))
          when "checkpoint"
            other = JSON.parse((TEST_FIXTURE_DIR/"attestation/dispatch-rebottle.json").read)
            log_entry(bundle).fetch("inclusionProof")["checkpoint"] =
              log_entry(other).fetch("inclusionProof").fetch("checkpoint")
          when "ca", "missing_sct", "altered_sct"
            if %w[missing_sct altered_sct].include?(tamper)
              # Changing the SCT also invalidates the certificate and its log binding.
              allow(verifier).to receive(:verify_certificate).and_return([leaf, issuer])
              allow(verifier).to receive(:verify_body)
            end
            case tamper
            when "ca" then leaf.sign(OpenSSL::PKey::EC.generate("prime256v1"), "SHA256")
            when "missing_sct"
              leaf.extensions = leaf.extensions.reject { |ext| ext.oid == "ct_precert_scts" }
            when "altered_sct"
              leaf.extensions = leaf.extensions.map do |ext|
                next ext if ext.oid != "ct_precert_scts"

                bytes = ext.value_der.dup
                bytes.setbyte(-1, bytes.bytes.fetch(-1) ^ 1)
                OpenSSL::X509::Extension.new(ext.oid, bytes)
              end
            end
            leaf.tbs_bytes
            bundle.fetch("verificationMaterial").fetch("certificate")["rawBytes"] =
              [leaf.to_der].pack("m0")
          when "altered_dsse"
            envelope_signature(bundle)["sig"] = corrupt_signature(envelope_signature(bundle).fetch("sig"))
            allow(verifier).to receive(:verify_body) # The log also binds the signature.
          when "log_payload", "log_signature", "log_certificate"
            # Isolate the binding check from the log signatures covering the body.
            allow(verifier).to receive_messages(verify_promise: nil, verify_inclusion: nil)
            logged = JSON.parse(body)
            case tamper
            when "log_payload" then logged.fetch("spec").fetch("payloadHash")["value"] = "0" * 64
            when "log_signature" then logged.fetch("spec").fetch("signatures").fetch(0)["signature"] =
                                        ["other"].pack("m0")
            when "log_certificate" then logged.fetch("spec").fetch("signatures").fetch(0)["verifier"] =
                                          ["other"].pack("m0")
            end
            log_entry(bundle)["canonicalizedBody"] = [JSON.generate(logged)].pack("m0")
          when "statement_type"
            statement = JSON.parse(payload).merge("_type" => "https://in-toto.io/Statement/v0.1")
            bundle.fetch("dsseEnvelope")["payload"] = [JSON.generate(statement)].pack("m0")
          end

          expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
            .to raise_error(Homebrew::Attestation::InvalidAttestationError)
        end
      end

      it "rejects a bundle with another OIDC issuer" do
        # Changing the issuer also invalidates the certificate, SCT and log binding.
        allow(verifier).to receive_messages(verify_certificate: [leaf, issuer], verify_sct: nil, verify_body: nil)
        replace_issuer("1.3.6.1.4.1.57264.1.1", "https://example.com")
        leaf.tbs_bytes
        certificate_der = leaf.to_der
        expect(OpenSSL::X509::Certificate.new(certificate_der).extensions)
          .to include(have_attributes(oid: "1.3.6.1.4.1.57264.1.1", value_der: "https://example.com"))
        bundle.fetch("verificationMaterial").fetch("certificate")["rawBytes"] =
          [certificate_der].pack("m0")

        expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError,
                          "attestation verification failed: OIDC issuer does not match")
      end

      it "rejects a proof size not signed by the checkpoint" do
        inclusion = log_entry(bundle).fetch("inclusionProof")
        inclusion["treeSize"] = (inclusion.fetch("treeSize").to_i + 1).to_s

        expect { described_class.verify_bundle(JSON.generate(bundle), digest, signing_repo) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /checkpoint/)
      end

      it "rejects a bad inclusion promise signature" do
        promise = entry.inclusion_promise.dup
        promise.setbyte(-1, promise.bytes.fetch(-1) ^ 1)

        expect { verifier.verify_promise(entry.with(inclusion_promise: promise), key) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /inclusion promise/)
      end

      it "rejects an inclusion proof for another root" do
        expect { verifier.verify_inclusion(body, proof.with(encoded_root_hash: ["x" * 32].pack("m0"))) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /inclusion proof/)
      end

      it "rejects a signed checkpoint for another root" do
        expect do
          verifier.verify_checkpoint(proof.with(encoded_root_hash: ["x" * 32].pack("m0")), key_id, key)
        end
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /checkpoint/)
      end

      it "rejects a signed checkpoint for another tree size" do
        expect { verifier.verify_checkpoint(proof.with(tree_size: proof.tree_size + 1), key_id, key) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /checkpoint/)
      end

      it "rejects a bad checkpoint signature" do
        checkpoint = proof.checkpoint.sub(/(\S+)\n\z/) do
          signature = corrupt_signature(Regexp.last_match(1))
          "#{signature}\n"
        end

        expect { verifier.verify_checkpoint(proof.with(checkpoint:), key_id, key) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /checkpoint/)
      end

      it "rejects a certificate signed by another CA" do
        leaf.sign(OpenSSL::PKey::EC.generate("prime256v1"), "SHA256")

        expect { verifier.verify_certificate(leaf, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /Fulcio/)
      end

      it "rejects a certificate outside its validity period" do
        expect { verifier.verify_certificate(leaf, leaf.not_after + 1) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /signing time/)
      end

      it "requires digital signature key usage" do
        leaf.extensions = leaf.extensions.reject { |ext| ext.oid == "keyUsage" }

        expect { verifier.verify_certificate(leaf, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /digital signature/)
      end

      it "requires code signing extended key usage" do
        leaf.extensions = leaf.extensions.reject { |ext| ext.oid == "extendedKeyUsage" }

        expect { verifier.verify_certificate(leaf, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /code signing/)
      end

      it "verifies the SCT when the precertificate has a stale DER encoding" do
        precertificate = leaf.dup
        allow(leaf).to receive(:dup).and_return(precertificate)
        allow(precertificate).to receive(:to_der).and_return(leaf.to_der)

        expect { verifier.verify_sct(leaf, issuer, time) }.not_to raise_error
      end

      it "requires an embedded SCT" do
        trusted_issuer = issuer
        leaf.extensions = leaf.extensions.reject { |ext| ext.oid == "ct_precert_scts" }

        expect { verifier.verify_sct(leaf, trusted_issuer, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /missing SCT/)
      end

      it "rejects an altered SCT signature" do
        trusted_issuer = issuer
        leaf.extensions = leaf.extensions.map do |ext|
          next ext if ext.oid != "ct_precert_scts"

          bytes = ext.value_der.dup
          bytes.setbyte(-1, bytes.bytes.fetch(-1) ^ 1)
          OpenSSL::X509::Extension.new(ext.oid, bytes)
        end

        expect { verifier.verify_sct(leaf, trusted_issuer, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /SCT signature/)
      end

      def replace_issuer(issuer_extension, issuer_url)
        value = if issuer_extension == "1.3.6.1.4.1.57264.1.8"
          OpenSSL::ASN1::UTF8String.new(issuer_url).to_der
        else
          issuer_url
        end
        leaf.extensions = leaf.extensions.reject do |extension|
          %w[1.3.6.1.4.1.57264.1.1 1.3.6.1.4.1.57264.1.8].include?(extension.oid)
        end + [OpenSSL::X509::Extension.new(issuer_extension, value)]
      end

      test_each(%w[1.3.6.1.4.1.57264.1.1 1.3.6.1.4.1.57264.1.8]) do |issuer_extension|
        it "accepts the exact GitHub Actions issuer in #{issuer_extension}" do
          replace_issuer(issuer_extension, Homebrew::Attestation::GITHUB_ACTIONS_ISSUER)

          expect { verifier.verify_identity(leaf, policy, time) }.not_to raise_error
        end
      end

      test_each(%w[1.3.6.1.4.1.57264.1.1 1.3.6.1.4.1.57264.1.8].product(%w[
        https://example.com
        https://token.actions.githubusercontent.com.example.com
        https://token.actions.githubusercontent.com@example.com
        https://example.com/https://token.actions.githubusercontent.com
        https://token.actions.githubusercontent.com/extra
      ])) do |(issuer_extension, issuer_url)|
        it "rejects the issuer #{issuer_url} in #{issuer_extension}" do
          replace_issuer(issuer_extension, issuer_url)

          expect { verifier.verify_identity(leaf, policy, time) }
            .to raise_error(Homebrew::Attestation::InvalidAttestationError, /OIDC issuer/)
        end
      end

      test_each_hash({
        "a self-hosted runner"                     => ["1.3.6.1.4.1.57264.1.11", "self-hosted", /runner environment/],
        "a fork"                                   => ["1.3.6.1.4.1.57264.1.12", "https://github.com/fork/homebrew-core",
                                                       /source repository does/],
        "another branch"                           => ["1.3.6.1.4.1.57264.1.14", "refs/heads/other",
                                                       /source repository ref/],
        "a renamed repository with a different ID" => ["1.3.6.1.4.1.57264.1.15", "52855517", /source repository ID/],
        "another owner of the same name"           => ["1.3.6.1.4.1.57264.1.17", "1503513", /owner ID/],
      }) do |signer, (extension_id, value, message)|
        it "rejects a certificate for #{signer}" do
          leaf.extensions = leaf.extensions.reject { |extension| extension.oid == extension_id } +
                            [OpenSSL::X509::Extension.new(extension_id, OpenSSL::ASN1::UTF8String.new(value).to_der)]

          expect { verifier.verify_identity(leaf, policy, time) }
            .to raise_error(Homebrew::Attestation::InvalidAttestationError, message)
        end
      end

      it "requires the runner environment claim" do
        leaf.extensions = leaf.extensions.reject { |extension| extension.oid == "1.3.6.1.4.1.57264.1.11" }

        expect { verifier.verify_identity(leaf, policy, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /runner environment/)
      end

      it "rejects a repeated claim" do
        leaf.extensions += [OpenSSL::X509::Extension.new("1.3.6.1.4.1.57264.1.11",
                                                         OpenSSL::ASN1::UTF8String.new("self-hosted").to_der)]

        expect { verifier.verify_identity(leaf, policy, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /runner environment/)
      end

      test_each_hash({
        "another workflow"      => "Homebrew/homebrew-core/.github/workflows/tests.yml@refs/heads/main",
        "a pull request"        => "Homebrew/homebrew-core/.github/workflows/dispatch-rebottle.yml@refs/pull/1/merge",
        "a fork"                => "fork/homebrew-core/.github/workflows/dispatch-rebottle.yml@refs/heads/main",
        "a longer workflow URI" => "Homebrew/homebrew-core/.github/workflows/dispatch-rebottle.yml@refs/heads/main/x",
      }) do |signer, workflow|
        it "rejects a certificate signed by #{signer}" do
          leaf.extensions = leaf.extensions.reject { |extension| extension.oid == "subjectAltName" } + [
            OpenSSL::X509::ExtensionFactory.new.create_extension("subjectAltName",
                                                                 "URI:https://github.com/#{workflow}", true),
          ]

          expect { verifier.verify_identity(leaf, policy, time) }
            .to raise_error(Homebrew::Attestation::InvalidAttestationError, /SANs/)
        end
      end

      it "requires the workflow to have run from the source repository ref" do
        leaf.extensions = leaf.extensions.reject { |extension| extension.oid == "1.3.6.1.4.1.57264.1.14" } + [
          OpenSSL::X509::Extension.new("1.3.6.1.4.1.57264.1.14",
                                       OpenSSL::ASN1::UTF8String.new("refs/heads/master").to_der),
        ]

        expect { verifier.verify_identity(leaf, policy, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /SANs/)
      end

      test_each_hash({
        "backfill"                      => ["0ebfa147cd1a513a86323167ab696a94b490dcd215d6685188bc376bf1313953",
                                            "refs/heads/main", Time.utc(2024, 3, 9)],
        "publish-commit-bottles-master" => ["345e99255a69e9cb188a5a8e6bd8e6f50c334830c8a72877fc6b504c95e5cbd1",
                                            "refs/heads/master", Time.utc(2024, 12, 1)],
      }) do |fixture, (digest, ref, cutoff)|
        it "rejects a #{fixture} bundle signed after the #{ref} cutoff" do
          policies = Homebrew::Attestation::Verifier::POLICIES.map do |trusted|
            trusted.with(refs: trusted.refs.merge(ref => cutoff))
          end
          stub_const("Homebrew::Attestation::Verifier::POLICIES", policies)

          backfill = fixture == "backfill"
          expect { verified_digests(fixture, digest, policies.fetch(backfill ? 1 : 0).repository) }
            .to raise_error(Homebrew::Attestation::InvalidAttestationError, /signed after the #{ref} cutoff/)
        end
      end

      it "rejects a DSSE signature over another payload" do
        expect { verifier.verify_dsse(leaf, "#{payload} ", signature) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /DSSE signature/)
      end

      it "rejects a log body for another envelope" do
        expect { verifier.verify_body(body, "#{payload} ", signature, leaf) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /log body/)
      end

      it "requires a SLSA provenance v1 predicate" do
        statement = JSON.parse(payload).merge("predicateType" => "https://slsa.dev/provenance/v0.2")

        expect { verifier.verify_statement(JSON.generate(statement), digest) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /SLSA provenance v1/)
      end

      it "requires an in-toto v1 statement" do
        statement = JSON.parse(payload).merge("_type" => "https://in-toto.io/Statement/v0.1")

        expect { verifier.verify_statement(JSON.generate(statement), digest) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /in-toto v1/)
      end

      test_each([:tlogs, :ctlogs, :certificateAuthorities].product([:start, :end])) do |(kind, boundary)|
        it "requires #{kind} #{boundary} to cover the integrated time" do
          root = JSON.parse((HOMEBREW_LIBRARY_PATH/"attestation/trusted_root.json").read, symbolize_names: true)
          root.fetch(kind).each do |authority|
            period = if kind == :certificateAuthorities
              authority.fetch(:validFor)
            else
              authority.fetch(:publicKey).fetch(:validFor)
            end
            start_boundary = boundary == :start
            period[boundary] = (time + (start_boundary ? 1 : -1)).iso8601
          end
          trusted_root = verifier.parse_trusted_root(JSON.generate(root))
          allow(verifier).to receive(:trusted_root).and_return(trusted_root)

          expect do
            if kind == :certificateAuthorities
              verifier.verify_certificate(leaf, time)
            else
              log_keys = if kind == :tlogs
                trusted_root.transparency_logs
              else
                trusted_root.certificate_transparency_logs
              end
              verifier.trusted_key(log_keys, log_keys.fetch(-1).log_id, time)
            end
          end.to raise_error(Homebrew::Attestation::InvalidAttestationError)
        end
      end

      it "rejects log integers outside canonical JSON precision" do
        expect { verifier.log_integer((2**53).to_s) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /out of range/)
      end

      it "rejects an unknown log key ID" do
        expect { verifier.trusted_key(verifier.trusted_root.transparency_logs, "x" * 32, time) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /no trusted/)
      end

      it "requires the expected subject digest" do
        expect { verifier.verify_statement(payload, "0" * 64) }
          .to raise_error(Homebrew::Attestation::InvalidAttestationError, /subjects matches/)
      end
    end

    test_each(%w[shape parsing verification]) do |failure|
      it "names the opt-out once when #{failure} fails an installation" do
        allow(fake_bottle).to receive(:name).and_return("fakebottle")
        allow(described_class).to receive(:check_formula_attestation) do
          input = case failure
          when "shape" then "{}"
          when "parsing" then "{"
          else JSON.generate(bundle)
          end
          described_class.verify_bundle(input, "0" * 64, signing_repo)
        end

        expect { Utils::Attestation.check_attestation(fake_bottle, quiet: true) }
          .to raise_error(CannotInstallFormulaError) { |error|
            expect(error.message.scan("HOMEBREW_NO_VERIFY_ATTESTATIONS=1"))
              .to eq(["HOMEBREW_NO_VERIFY_ATTESTATIONS=1"])
          }
      end
    end
  end
end
