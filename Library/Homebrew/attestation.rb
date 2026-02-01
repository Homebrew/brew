# typed: strict
# frozen_string_literal: true

require "date"
require "json"
require "fileutils"
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
    BACKFILL_CUTOFF = T.let(DateTime.new(2024, 3, 14).freeze, DateTime)

    # Cache durations for offline verification
    # @api private
    BUNDLE_CACHE_DURATION = T.let(86400, Integer) # 24 hours - bundles are immutable
    # @api private
    TRUSTED_ROOT_CACHE_DURATION = T.let(86400, Integer) # 24 hours

    # Raised when the attestation was not found.
    #
    # @api private
    class MissingAttestationError < RuntimeError; end

    # Raised when attestation verification fails.
    #
    # @api private
    class InvalidAttestationError < RuntimeError; end

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

    # Raised when bundle fetch fails during offline verification.
    #
    # @api private
    class BundleFetchError < RuntimeError; end

    # Returns whether attestation verification is enabled.
    #
    # @api private
    sig { returns(T::Boolean) }
    def self.enabled?
      return false if Homebrew::EnvConfig.no_verify_attestations?

      Homebrew::EnvConfig.verify_attestations?
    end

    # Returns whether offline verification is configured.
    #
    # @api private
    sig { returns(T::Boolean) }
    def self.offline_verification?
      Homebrew::EnvConfig.attestation_bundle_url.present?
    end

    # Returns a path to a suitable `gh` executable for attestation verification.
    #
    # @api private
    sig { returns(Pathname) }
    def self.gh_executable
      @gh_executable ||= T.let(nil, T.nilable(Pathname))
      return @gh_executable if @gh_executable.present?

      # NOTE: We set HOMEBREW_NO_VERIFY_ATTESTATIONS when installing `gh` itself,
      #       to prevent a cycle during bootstrapping. This can eventually be resolved
      #       by vendoring a pure-Ruby Sigstore verifier client.
      @gh_executable = with_env(HOMEBREW_NO_VERIFY_ATTESTATIONS: "1") do
        ensure_executable!("gh", reason: "verifying attestations", latest: true)
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

    # Check if a string looks like a URL (has a scheme).
    #
    # @api private
    sig { params(str: String).returns(T::Boolean) }
    def self.url?(str)
      str.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
    end

    # Validate that a digest is a valid hex string.
    #
    # @api private
    sig { params(digest: String).returns(T::Boolean) }
    def self.valid_digest?(digest)
      digest.match?(/\A[0-9a-f]{64}\z/i)
    end

    # Atomically write content to a file path.
    #
    # @api private
    # Sorbet requires explicit block parameter with yield
    # rubocop:disable Lint/UnusedMethodArgument
    sig { params(path: Pathname, blk: T.proc.params(tmp: Pathname).void).void }
    def self.atomic_write(path, &blk)
      # rubocop:enable Lint/UnusedMethodArgument
      tmp_path = path.dirname/"#{path.basename}.#{Process.pid}.tmp"
      begin
        yield(tmp_path)
        FileUtils.mv(tmp_path, path)
      # Sorbet requires explicit exception class
      # rubocop:disable Style/RescueStandardError
      rescue StandardError
        # rubocop:enable Style/RescueStandardError
        tmp_path.unlink if tmp_path.exist?
        raise
      end
    end

    # Fetches an attestation bundle from the configured bundle URL.
    #
    # @param digest [String] The SHA256 digest of the bottle (hex string, no algorithm prefix)
    # @return [Pathname, nil] Path to the downloaded bundle, or nil if not configured
    # @raise [BundleFetchError] if the fetch fails
    #
    # @api private
    sig { params(digest: String).returns(T.nilable(Pathname)) }
    def self.fetch_attestation_bundle(digest)
      bundle_url_template = Homebrew::EnvConfig.attestation_bundle_url
      return if bundle_url_template.blank?

      # Validate digest to prevent URL injection
      raise BundleFetchError, "Invalid digest format: #{digest}" unless valid_digest?(digest)

      # Substitute {digest} placeholder in URL template
      bundle_url = bundle_url_template.gsub("{digest}", digest)

      bundle_cache_dir = HOMEBREW_CACHE/"attestation-bundles"
      bundle_cache_dir.mkpath
      # Use .jsonl extension - bundles may contain multiple attestations
      bundle_path = bundle_cache_dir/"#{digest}.jsonl"

      # Use cached bundle if it exists and is recent
      if bundle_path.exist? && (Time.now - bundle_path.mtime) < BUNDLE_CACHE_DURATION
        odebug "Using cached attestation bundle for #{digest}"
        return bundle_path
      end

      odebug "Fetching attestation bundle from #{bundle_url}"

      begin
        # Download to temp file then atomically move to cache
        atomic_write(bundle_path) do |tmp_path|
          Utils::Curl.curl_download(bundle_url, to: tmp_path, try_partial: false)
        end
      rescue ErrorDuringExecution => e
        raise BundleFetchError, "Failed to fetch attestation bundle: #{e.message}"
      end

      bundle_path
    end

    # Returns the path to the trusted root, fetching it if necessary.
    #
    # @return [Pathname, nil] Path to the trusted root file, or nil if not configured
    # @raise [InvalidAttestationError] if trusted root cannot be obtained
    #
    # @api private
    sig { returns(T.nilable(Pathname)) }
    def self.trusted_root_path
      trusted_root = Homebrew::EnvConfig.attestation_trusted_root
      return if trusted_root.blank?

      # If it's a URL, fetch and cache it
      return fetch_trusted_root_from_url(trusted_root) if url?(trusted_root)

      # Otherwise, treat it as a local file path
      path = Pathname.new(trusted_root)
      raise InvalidAttestationError, "Trusted root file not found: #{trusted_root}" unless path.exist?

      path
    end

    # Fetches trusted root from a URL with caching.
    #
    # @api private
    sig { params(url: String).returns(Pathname) }
    def self.fetch_trusted_root_from_url(url)
      trusted_root_cache = HOMEBREW_CACHE/"attestation-trusted-root.json"

      # Check if cached version is recent enough
      if trusted_root_cache.exist?
        cache_age = Time.now - trusted_root_cache.mtime
        if cache_age < TRUSTED_ROOT_CACHE_DURATION
          odebug "Using cached trusted root (age: #{cache_age.to_i}s)"
          return trusted_root_cache
        end
      end

      odebug "Fetching trusted root from #{url}"

      begin
        atomic_write(trusted_root_cache) do |tmp_path|
          Utils::Curl.curl_download(url, to: tmp_path, try_partial: false)
        end
        trusted_root_cache
      rescue ErrorDuringExecution => e
        # Fail-closed by default: don't use stale trusted roots
        if trusted_root_cache.exist? && Homebrew::EnvConfig.attestation_allow_stale_root?
          opoo "Failed to refresh trusted root, using cached version: #{e.message}"
          opoo "WARNING: Cached trusted root may contain revoked key material"
          return trusted_root_cache
        end

        if trusted_root_cache.exist?
          raise InvalidAttestationError,
                "Failed to refresh trusted root and stale roots are not allowed. " \
                "Set HOMEBREW_ATTESTATION_ALLOW_STALE_ROOT=1 to use cached version. Error: #{e.message}"
        end

        raise InvalidAttestationError, "Failed to fetch trusted root: #{e.message}"
      end
    end

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
             signing_workflow: T.nilable(String), subject: T.nilable(String)).returns(T::Hash[T.untyped, T.untyped])
    }
    def self.check_attestation(bottle, signing_repo, signing_workflow = nil, subject = nil)
      cmd = ["attestation", "verify", bottle.cached_download, "--repo", signing_repo, "--format", "json"]

      # Determine if we're doing offline verification
      if offline_verification?
        # Get the bottle's digest for bundle lookup (hex string, no prefix)
        digest = bottle.resource.checksum&.hexdigest
        raise InvalidAttestationError, "Bottle has no checksum for bundle lookup" if digest.blank?

        # Fetch attestation bundle
        begin
          bundle_path = fetch_attestation_bundle(digest)
          if bundle_path.present?
            cmd += ["--bundle", bundle_path.to_s]
            odebug "Using attestation bundle: #{bundle_path}"
          end
        rescue BundleFetchError => e
          raise InvalidAttestationError, "Offline verification failed: #{e.message}"
        end

        # Get trusted root (required for offline verification)
        root_path = trusted_root_path
        if root_path.present?
          cmd += ["--custom-trusted-root", root_path.to_s]
          odebug "Using trusted root: #{root_path}"
        else
          raise InvalidAttestationError,
                "HOMEBREW_ATTESTATION_TRUSTED_ROOT must be set for offline verification"
        end
      end

      cmd += ["--cert-identity", signing_workflow] if signing_workflow.present?

      # Set up environment
      env = { "GH_HOST" => "github.com" }
      secrets = T.let([], T::Array[String])

      # Online verification requires GitHub credentials
      unless offline_verification?
        credentials = GitHub::API.credentials
        raise GhAuthNeeded, "missing credentials" if credentials.blank?

        env["GH_TOKEN"] = credentials
        secrets = [credentials]
      end

      begin
        result = system_command!(gh_executable, args: cmd, env: env,
                                 secrets: secrets, print_stderr: false, chdir: HOMEBREW_TEMP)
      rescue ErrorDuringExecution => e
        if e.status.exitstatus == 1 && e.stderr.include?("unknown command")
          raise GhIncompatible, "gh CLI is incompatible with attestations"
        end

        # Even if we have credentials, they may be invalid or malformed.
        if e.status.exitstatus == 4 || e.stderr.include?("HTTP 401: Bad credentials")
          raise GhAuthInvalid, "invalid credentials"
        end

        raise MissingAttestationError, "attestation not found: #{e}" if e.stderr.include?("HTTP 404: Not Found")

        raise InvalidAttestationError, "attestation verification failed: #{e}"
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
      # `actions/attest-build-provenance` action.
      subject = bottle.filename.to_s if subject.blank?

      attestation = if bottle.tag.to_sym == :all
        # :all-tagged bottles are created by `brew bottle --merge`, and are not directly
        # bound to their own filename (since they're created by deduplicating other filenames).
        # To verify these, we parse each attestation subject and look for one with a matching
        # formula (name, version), but not an exact tag match.
        # This is sound insofar as the signature has already been verified. However,
        # longer term, we should also directly attest to `:all`-tagged bottles.
        attestations.find do |a|
          candidate_subjects = a.dig("verificationResult", "statement", "subject")
          candidate_subjects.any? do |candidate|
            candidate["name"].start_with? "#{bottle.filename.name}--#{bottle.filename.version}"
          end
        end
      else
        attestations.find do |a|
          candidate_subjects = a.dig("verificationResult", "statement", "subject")
          candidate_subjects.any? { |candidate| candidate["name"] == subject }
        end
      end

      raise InvalidAttestationError, "no attestation matches subject: #{subject}" if attestation.blank?

      attestation
    end

    ATTESTATION_MAX_RETRIES = 5

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
    sig { params(bottle: Bottle).returns(T::Hash[T.untyped, T.untyped]) }
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
        url_sha256 = if EnvConfig.bottle_domain == HOMEBREW_BOTTLE_DEFAULT_DOMAIN
          Digest::SHA256.hexdigest(bottle.url)
        else
          # If our bottle is coming from a mirror, we need to recompute the expected
          # non-mirror URL to make the hash match.
          checksum = bottle.resource.checksum
          odie "#{bottle.resource.name} checksum is nil" if checksum.nil?
          path, = Utils::Bottles.path_resolved_basename HOMEBREW_BOTTLE_DEFAULT_DOMAIN, bottle.name,
                                                        checksum, bottle.filename
          url = "#{HOMEBREW_BOTTLE_DEFAULT_DOMAIN}/#{path}"

          Digest::SHA256.hexdigest(url)
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

      sleep_time = 3 ** @attestation_retry_count[bottle]
      opoo "Failed to verify attestation. Retrying in #{sleep_time}s..."
      sleep sleep_time if ENV["HOMEBREW_TESTS"].blank?
      @attestation_retry_count[bottle] += 1
      retry
    end
  end
end
