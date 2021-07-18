# typed: true
# frozen_string_literal: true

module Utils
  # Helper functions for BuildPulse integration
  module Buildpulse
    extend T::Sig

    module_function

    sig { returns(T::Boolean) }
    def available?
      return @available if defined?(@available)

      @available = ENV["HOMEBREW_BUILDPULSE_ACCESS_KEY_ID"].present? &&
                   ENV["HOMEBREW_BUILDPULSE_SECRET_ACCESS_KEY"].present? &&
                   ENV["HOMEBREW_BUILDPULSE_ACCOUNT_ID"].present? &&
                   ENV["HOMEBREW_BUILDPULSE_REPOSITORY_ID"].present?
    end

    sig { params(test_results_dir: T.any(String, Pathname)).void }
    def upload_results(test_results_dir)
      require "formula"

      unless Formula["buildpulse-test-reporter"].any_version_installed?
        ohai "Installing `buildpulse-test-reporter` for reporting test flakiness..."
        with_env(HOMEBREW_NO_AUTO_UPDATE: "1", HOMEBREW_NO_BOOTSNAP: "1") do
          safe_system HOMEBREW_BREW_FILE, "install", "buildpulse-test-reporter"
        end
      end

      ENV["BUILDPULSE_ACCESS_KEY_ID"] = ENV["HOMEBREW_BUILDPULSE_ACCESS_KEY_ID"]
      ENV["BUILDPULSE_SECRET_ACCESS_KEY"] = ENV["HOMEBREW_BUILDPULSE_SECRET_ACCESS_KEY"]

      ohai "Sending test results to BuildPulse"

      safe_system Formula["buildpulse-test-reporter"].opt_bin/"buildpulse-test-reporter",
                  "submit", test_results_dir.to_s,
                  "--account-id", ENV["HOMEBREW_BUILDPULSE_ACCOUNT_ID"],
                  "--repository-id", ENV["HOMEBREW_BUILDPULSE_REPOSITORY_ID"]
    end
  end
end
