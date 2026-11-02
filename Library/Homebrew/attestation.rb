# typed: strict
# frozen_string_literal: true

require "utils/executable"

require "date"
require "json"
require "tempfile"
require "utils/popen"
require "utils/github/api"
require "exceptions"
require "system_command"
require "utils/output"

module Homebrew
  module Attestation
    extend SystemCommand::Mixin
    extend Utils::Output::Mixin

    # @api private
    HOMEBREW_CORE_REPO = "Homebrew/homebrew-core"

    # @api private
    BACKFILL_REPO = "trailofbits/homebrew-brew-verify"

    # No backfill attestations after this date are considered valid.
    #
    # This date is shortly after the backfill operation for homebrew-core
    # completed, as can be seen here: <https://github.com/trailofbits/homebrew-brew-verify/attestations>.
    #
    # In effect, this means that, even if an attacker is able to compromise the backfill
    # signing workflow, they will be unable to convince a verifier to accept their newer,
    # malicious backfilled signatures.
    #
    # @api private
    BACKFILL_CUTOFF = DateTime.new(2024, 3, 14).freeze

    # @api private
    BULK_LIST_MAX_DIGESTS = 1024

    # @api private
    BULK_LIST_PAGE_SIZE = 100

    # Raised when the attestation was not found.
    #
    # @api private
    class MissingAttestationError < RuntimeError; end

    # Raised when attestation verification fails.
    #
    # @api private
    class InvalidAttestationError < RuntimeError; end

    # Raised when attestation verification cannot complete due to the GitHub API rate limit.
    #
    # @api private
    class RateLimitExceededError < RuntimeError; end

    # Raised when bottle attestation verification is unsupported for a tap.
    #
    # @api private
    class UnsupportedTapError < RuntimeError; end

    # Raised if attestation verification cannot continue due to missing
    # credentials.
    #
    # @api private
    class GhAuthNeeded < RuntimeError; end

    # Raised if attestation verification cannot continue due to invalid
    # credentials.
    #
    # @api private
    class GhAuthInvalid < RuntimeError; end

    # Raised if attestation verification cannot continue due to `gh`
    # being incompatible with attestations, typically because it's too old.
    #
    # @api private
    class GhIncompatible < RuntimeError; end

    # Returns a path to a suitable `gh` executable for attestation verification.
    #
    # @api private
    sig { returns(Pathname) }
    def self.gh_executable
      @gh_executable ||= T.let(nil, T.nilable(Pathname))
      return @gh_executable if @gh_executable

      # NOTE: We set HOMEBREW_NO_VERIFY_ATTESTATIONS when installing `gh` itself,
      #       to prevent a cycle during bootstrapping. This can eventually be resolved
      #       by vendoring a pure-Ruby Sigstore verifier client.
      @gh_executable = with_env(HOMEBREW_NO_VERIFY_ATTESTATIONS: "1") do
        Utils::Executable.ensure!("gh", reason: "verifying attestations", latest: true)
      end
    end

    # Prioritize installing `gh` first if it's in the formula list
    # or check for the existence of the `gh` executable elsewhere.
    #
    # This ensures that a valid version of `gh` is installed before
    # we use it to check the attestations of any other formulae we
    # want to install.
    #
    # @api private
    sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
    def self.sort_formulae_for_install(formulae)
      if (gh = formulae.find { |f| f.full_name == "gh" })
        [gh] | formulae
      else
        Homebrew::Attestation.gh_executable
        formulae
      end
    end

    # Listed attestation bundles as JSON lines, keyed by bottle SHA-256 and
    # then by organisation; an empty array means the organisation holds none.
    #
    # @api private
    sig { returns(T::Hash[String, T::Hash[String, T::Array[String]]]) }
    def self.prefetched_bundles
      @prefetched_bundles ||= T.let({}, T.nilable(T::Hash[String, T::Hash[String, T::Array[String]]]))
    end

    # Lists the formulae's homebrew-core bottle attestations in bulk so that
    # `check_attestation` can verify them offline. Failures are only logged:
    # an unlisted bottle is looked up online as before.
    #
    # @api private
    sig { params(formulae: T::Array[Formula]).void }
    def self.prefetch(formulae)
      return unless Homebrew::EnvConfig.verify_attestations?
      return if Homebrew::EnvConfig.no_github_api?
      return if GitHub::API.credentials.blank?

      digests = formulae.filter_map do |formula|
        bottle = formula.bottle if formula.tap&.core_tap?
        bottle.resource.checksum&.hexdigest if bottle
      end
      digests = digests.uniq - prefetched_bundles.keys
      return if digests.empty?

      [HOMEBREW_CORE_REPO, BACKFILL_REPO].each do |signing_repo|
        organisation = signing_organisation(signing_repo)
        listed = bulk_list_bundles(organisation, digests)
        digests.each do |digest|
          (prefetched_bundles[digest] ||= {})[organisation] = listed.fetch(digest, [])
        end
        digests -= listed.keys
        break if digests.empty?
      end
    rescue GitHub::API::Error, JSON::ParserError => e
      odebug "Failed to list attestations in bulk: #{e}"
    end

    # Returns inline bundles as JSON lines, keyed by digest.
    #
    # @api private
    sig { params(organisation: String, digests: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
    def self.bulk_list_bundles(organisation, digests)
      url = "#{GitHub::API_URL}/orgs/#{organisation}/attestations/bulk-list?per_page=#{BULK_LIST_PAGE_SIZE}"
      bundles = {}
      digests.each_slice(BULK_LIST_MAX_DIGESTS) do |slice|
        data = { subject_digests: slice.map { |digest| "sha256:#{digest}" } }
        page_url = url
        loop do
          response = GitHub::API.open_rest(page_url, data:, request_method: :POST)
          break unless response.is_a?(Hash)

          listed = response["attestations_subject_digests"]
          listed = {} unless listed.is_a?(Hash)
          listed.each do |subject_digest, attestations|
            next unless attestations.is_a?(Array)

            # Attestations with only a `bundle_url` are left to the online lookup.
            lines = attestations.filter_map do |attestation|
              bundle = attestation["bundle"] if attestation.is_a?(Hash)
              JSON.generate(bundle) if bundle.is_a?(Hash)
            end
            next if lines.empty?

            (bundles[subject_digest.to_s.delete_prefix("sha256:")] ||= []).concat(lines)
          end

          page_info = response["page_info"]
          cursor = page_info["next"] if page_info.is_a?(Hash) && page_info["has_next"]
          break if cursor.blank?

          next_url = "#{url}&after=#{URI.encode_www_form_component(cursor)}"
          break if next_url == page_url

          page_url = next_url
        end
      end
      bundles
    end

    # @api private
    sig { params(signing_repo: String).returns(String) }
    def self.signing_organisation(signing_repo) = signing_repo.split("/").fetch(0)

    # Verifies the given bottle against a cryptographic attestation of build provenance.
    #
    # The provenance is verified as originating from `signing_repository`, which is a `String`
    # that should be formatted as a GitHub `owner/repository`.
    #
    # Callers may additionally pass in `signing_workflow`, which will scope the attestation
    # down to an exact GitHub Actions workflow, in
    # `https://github/OWNER/REPO/.github/workflows/WORKFLOW.yml@REF` format.
    #
    # @return [Hash] the JSON-decoded response.
    # @raise [GhAuthNeeded] on any authentication failures
    # @raise [InvalidAttestationError] on any verification failures
    #
    # @api private
    sig {
      params(bottle: Bottle, signing_repo: String,
             signing_workflow: T.nilable(String), subject: T.nilable(String)).returns(T::Hash[String, T.untyped])
    }
    def self.check_attestation(bottle, signing_repo, signing_workflow = nil, subject = nil)
      cmd = ["attestation", "verify", bottle.cached_download, "--repo", signing_repo, "--format",
             "json"]

      cmd += ["--cert-identity", signing_workflow] if signing_workflow.present?

      # Fail early if we have no credentials. The command below invariably
      # fails without them, so this saves us an unnecessary subshell.
      credentials = GitHub::API.credentials
      raise GhAuthNeeded, "missing credentials" if credentials.blank?

      digest = Downloadable.verification_cache.sha256(bottle.cached_download)
      lines = prefetched_bundle_lines(bottle, digest, signing_organisation(signing_repo))
      bundle_path = nil
      begin
        if lines
          count = Utils.pluralize("listed attestation", lines.count, include_count: true)
          odebug "Verifying #{bottle.filename} against #{count} from #{signing_repo}"
          bundle_file = Tempfile.create(["attestations-", ".jsonl"], HOMEBREW_TEMP)
          bundle_path = Pathname(bundle_file.path)
          begin
            bundle_file.puts(lines)
          ensure
            bundle_file.close
          end
          cmd += ["--bundle", bundle_path]
        end

        result = system_command!(gh_executable, args: cmd,
                                 env: { "GH_TOKEN" => credentials, "GH_HOST" => "github.com" },
                                 secrets: [credentials], print_stderr: false, chdir: HOMEBREW_TEMP)
      rescue ErrorDuringExecution => e
        if e.exitstatus == 1 && e.stderr.include?("unknown command")
          raise GhIncompatible, "gh CLI is incompatible with attestations"
        end

        # Even if we have credentials, they may be invalid or malformed.
        if e.exitstatus == 4 || e.stderr.include?("HTTP 401: Bad credentials")
          raise GhAuthInvalid, "invalid credentials"
        end

        if e.stderr.match?(/HTTP (?:403|429)\b.*(?:API rate limit exceeded|exceeded a secondary rate limit)/)
          raise RateLimitExceededError, "GitHub API rate limit exceeded: #{e}"
        end

        # The API used to return 404 but now can return 200 with an empty array.
        # We match the no attestation case precisely as there are similarly worded errors.
        if e.stderr.include?("HTTP 404: Not Found") || e.stderr.match?(/: no attestations found\R/)
          raise MissingAttestationError, "attestation not found: #{e}"
        end

        raise InvalidAttestationError, "attestation verification failed: #{e}"
      ensure
        bundle_path&.unlink
      end

      begin
        attestations = JSON.parse(result.stdout)
      rescue JSON::ParserError
        raise InvalidAttestationError, "attestation verification returned malformed JSON"
      end

      # `gh attestation verify` returns a JSON array of one or more results,
      # for all attestations that match the input's digest. We want to additionally
      # filter these down to just the attestation whose subject(s) contain the bottle's name.
      # As of 2024-12-04 GitHub's Artifact Attestation feature can put multiple subjects
      # in a single attestation, so we check every subject in each attestation
      # and select the first attestation with a matching subject.
      # In particular, this happens with v2.0.0 and later of the
      # `actions/attest` action.
      subject = bottle.filename.to_s if subject.blank?

      attestation = attestations.find do |a|
        a.dig("verificationResult", "statement", "subject").any? do |candidate|
          next false if candidate.dig("digest", "sha256") != digest

          if bottle.tag.to_sym == :all
            # :all-tagged bottles are created by `brew bottle --merge`, and are not directly
            # bound to their own filename (since they're created by deduplicating other filenames).
            # To verify these, we parse each attestation subject and look for one with a matching
            # formula (name, version), but not an exact tag match.
            # This is sound insofar as the signature has already been verified. However,
            # longer term, we should also directly attest to `:all`-tagged bottles.
            candidate["name"].match?(
              /\A#{Regexp.escape("#{bottle.filename.name}--#{bottle.filename.version}")}\.
                [^.]+\.bottle(?:\.\d+)?\.tar\.gz\z/x,
            )
          else
            candidate["name"] == subject
          end
        end
      end

      raise InvalidAttestationError, "no attestation matches subject: #{subject}" if attestation.blank?

      attestation
    end

    # The listed bundles to verify the bottle against, or `nil` to look the
    # attestation up online.
    #
    # @raise [MissingAttestationError] when this organisation was listed empty and another has bundles
    #
    # @api private
    sig { params(bottle: Bottle, digest: String, organisation: String).returns(T.nilable(T::Array[String])) }
    def self.prefetched_bundle_lines(bottle, digest, organisation)
      bundles = prefetched_bundles.fetch(digest, {})
      lines = bundles[organisation]
      return if lines.nil?
      return lines unless lines.empty?

      # Leave digests no organisation holds to the online lookup in case the
      # listing was incomplete.
      return if bundles.values.all?(&:empty?)

      raise MissingAttestationError,
            "attestation not found: none listed from #{organisation} for #{bottle.filename}"
    end

    ATTESTATION_MAX_RETRIES = 5

    # Verifies a bottle against the attestation model for the formula's tap.
    #
    # @return [Hash] the JSON-decoded response
    # @raise [GhAuthNeeded] on any authentication failures
    # @raise [InvalidAttestationError] on any verification failures
    # @raise [UnsupportedTapError] when the bottle's tap cannot be attested safely
    #
    # @api private
    sig { params(bottle: Bottle).returns(T::Hash[String, T.untyped]) }
    def self.check_formula_attestation(bottle)
      formula = bottle.resource.owner
      formula = formula.owner if formula.is_a?(SoftwareSpec)
      unless formula.is_a?(Formula)
        raise UnsupportedTapError, "bottle is not associated with a formula tap."
      end

      tap = formula.tap
      if tap.nil?
        raise UnsupportedTapError,
              "#{formula.full_name} is not from a tap with supported bottle attestations."
      end
      return check_core_attestation(bottle) if tap.core_tap?

      if tap.custom_remote?
        raise UnsupportedTapError,
              "#{formula.full_name} is from #{tap.name}, which uses a non-default " \
              "remote and cannot be attested safely."
      end

      signing_repo = tap.remote_repository
      if signing_repo.blank?
        raise UnsupportedTapError,
              "#{formula.full_name} is from #{tap.name}, which does not resolve " \
              "to a GitHub repository for attestation verification."
      end

      return check_core_attestation(bottle) if signing_repo == HOMEBREW_CORE_REPO

      check_attestation(bottle, signing_repo)
    end

    # Verifies the given bottle against a cryptographic attestation of build provenance
    # from homebrew-core's CI, falling back on a "backfill" attestation for older bottles.
    #
    # This is a specialization of `check_attestation` for homebrew-core.
    #
    # @return [Hash] the JSON-decoded response
    # @raise [GhAuthNeeded] on any authentication failures
    # @raise [InvalidAttestationError] on any verification failures
    #
    # @api private
    sig { params(bottle: Bottle).returns(T::Hash[String, T.untyped]) }
    def self.check_core_attestation(bottle)
      begin
        # Ideally, we would also constrain the signing workflow here, but homebrew-core
        # currently uses multiple signing workflows to produce bottles
        # (e.g. `dispatch-build-bottle.yml`, `dispatch-rebottle.yml`, etc.).
        #
        # We could check each of these (1) explicitly (slow), (2) by generating a pattern
        # to pass into `--cert-identity-regex` (requires us to build up a Go-style regex),
        # or (3) by checking the resulting JSON for the expected signing workflow.
        #
        # Long term, we should probably either do (3) *or* switch to a single reusable
        # workflow, which would then be our sole identity. However, GitHub's
        # attestations currently do not include reusable workflow state by default.
        attestation = check_attestation bottle, HOMEBREW_CORE_REPO
        return attestation
      rescue MissingAttestationError
        odebug "falling back on backfilled attestation for #{bottle.filename}"

        # Our backfilled attestation is a little unique: the subject is not just the bottle
        # filename, but also has the bottle's hosted URL hash prepended to it.
        # This was originally unintentional, but has a virtuous side effect of further
        # limiting domain separation on the backfilled signatures (by committing them to
        # their original bottle URLs).
        url_sha256 = if EnvConfig.bottle_domain_custom?
          # If our bottle is coming from a mirror, we need to recompute the expected
          # non-mirror URL to make the hash match.
          checksum = bottle.resource.checksum
          odie "#{bottle.resource.name} checksum is nil" if checksum.nil?
          path, = Utils::Bottles.path_resolved_basename HOMEBREW_BOTTLE_DEFAULT_DOMAIN, bottle.name,
                                                        checksum, bottle.filename
          url = "#{HOMEBREW_BOTTLE_DEFAULT_DOMAIN}/#{path}"

          Digest::SHA256.hexdigest(url)
        else
          Digest::SHA256.hexdigest(bottle.url)
        end
        subject = "#{url_sha256}--#{bottle.filename}"

        # We don't pass in a signing workflow for backfill signatures because
        # some backfilled bottle signatures were signed from the 'backfill'
        # branch, and others from 'main' of trailofbits/homebrew-brew-verify
        # so the signing workflow is slightly different which causes some bottles to incorrectly
        # fail when checking their attestation. This shouldn't meaningfully affect security
        # because if somehow someone could generate false backfill attestations
        # from a different workflow we will still catch it because the
        # attestation would have been generated after our cutoff date.
        backfill_attestation = check_attestation bottle, BACKFILL_REPO, nil, subject
        timestamp = backfill_attestation.dig("verificationResult", "verifiedTimestamps",
                                             0, "timestamp")

        raise InvalidAttestationError, "backfill attestation is missing verified timestamp" if timestamp.nil?

        if DateTime.parse(timestamp) > BACKFILL_CUTOFF
          raise InvalidAttestationError, "backfill attestation post-dates cutoff"
        end
      end

      backfill_attestation
    rescue InvalidAttestationError
      @attestation_retry_count ||= T.let(Hash.new(0), T.nilable(T::Hash[Bottle, Integer]))
      raise if @attestation_retry_count[bottle] >= ATTESTATION_MAX_RETRIES

      # Retry online rather than against listed bundles that did not verify.
      prefetched_bundles.delete(Downloadable.verification_cache.sha256(bottle.cached_download))

      sleep_time = 3 ** @attestation_retry_count[bottle]
      opoo "Failed to verify attestation. Retrying in #{sleep_time}s..."
      sleep sleep_time if ENV["HOMEBREW_TESTS"].blank?
      @attestation_retry_count[bottle] += 1
      retry
    end
  end
end
