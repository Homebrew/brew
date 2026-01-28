# typed: strict
# frozen_string_literal: true

require "attestation"
require "bottle"
require "utils/output"

module Utils
  module Attestation
    extend Utils::Output::Mixin

    sig { params(bottle: Bottle, quiet: T::Boolean).void }
    def self.check_attestation(bottle, quiet: false)
      ohai "Verifying attestation for #{bottle.name}" unless quiet
      begin
        Homebrew::Attestation.check_core_attestation bottle
      rescue Homebrew::Attestation::GhIncompatible
        # A small but significant number of users have developer mode enabled
        # but *also* haven't upgraded in a long time, meaning that their `gh`
        # version is too old to perform attestations.
        raise CannotInstallFormulaError, <<~EOS
          The bottle for #{bottle.name} could not be verified.

          This typically indicates an outdated or incompatible `gh` CLI.

          Please confirm that you're running the latest version of `gh`
          by performing an upgrade before retrying:

            brew update
            brew upgrade gh
        EOS
      rescue Homebrew::Attestation::GhAuthInvalid
        # Only raise an error if we explicitly opted-in to verification.
        raise CannotInstallFormulaError, <<~EOS if Homebrew::EnvConfig.verify_attestations?
          The bottle for #{bottle.name} could not be verified.

          This typically indicates an invalid GitHub API token.

          If you have `$HOMEBREW_GITHUB_API_TOKEN` set, check it is correct
          or unset it and instead run:

            gh auth login
        EOS

        # If we didn't explicitly opt-in, then quietly opt-out in the case of invalid credentials.
        # Based on user reports, a significant number of users are running with stale tokens.
        ENV["HOMEBREW_NO_VERIFY_ATTESTATIONS"] = "1"
      rescue Homebrew::Attestation::GhAuthNeeded
        raise CannotInstallFormulaError, <<~EOS
          The bottle for #{bottle.name} could not be verified.

          This typically indicates a missing GitHub API token, which you
          can resolve either by setting `$HOMEBREW_GITHUB_API_TOKEN` or
          by running:

            gh auth login
        EOS
      rescue Homebrew::Attestation::MissingAttestationError, Homebrew::Attestation::InvalidAttestationError => e
        raise CannotInstallFormulaError, <<~EOS
          The bottle for #{bottle.name} has an invalid build provenance attestation.

          This may indicate that the bottle was not produced by the expected
          tap, or was maliciously inserted into the expected tap's bottle
          storage.

          Additional context:

          #{e}
        EOS
      end
    end
  end
end
