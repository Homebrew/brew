# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "formulary"
require "tap"
require "utils/github"
require "utils/user"

module Homebrew
  module Cmd
    class VersionInstall < AbstractCommand
      DEFAULT_TAP_REPOSITORY = "versions"
      private_constant :DEFAULT_TAP_REPOSITORY

      cmd_args do
        usage_banner "`version-install` <formula>[@<version>] [<version>]"
        description <<~EOS
          Extract a specific <version> of <formula> into a personal tap and install it.
          The default tap is <user>/#{DEFAULT_TAP_REPOSITORY}.
          <user> uses the GitHub username if available and the local username otherwise.
        EOS

        named_args [:formula, :version], min: 1, max: 2
      end

      sig { override.void }
      def run
        formula_input = args.named.fetch(0)
        version_input = args.named[1]

        if version_input.nil? || formula_input.include?("@")
          unless formula_input.include?("@")
            raise UsageError, "Specify a version with <formula> <version> or <formula>@<version>."
          end

          formula_base, _, version_from_input = formula_input.rpartition("@")
          odie "Invalid formula reference: #{formula_input}" if formula_base.empty? || version_from_input.empty?

          version_input ||= version_from_input
          odie "Version mismatch: #{formula_input} != #{version_input}" if version_from_input != version_input

          versioned_ref = formula_input
          formula_input = formula_base
        end

        tap_with_name = Tap.with_formula_name(formula_input)
        tap, base_name = tap_with_name || [nil, formula_input]
        base_name = base_name.downcase
                             .sub(/\b@(.*)\z\b/i, "")
        normalized_version = version_input.to_s
                                          .sub(/\D*(.+?)\D*$/, "\\1")
                                          .gsub(/\D+/, ".")
        versioned_name = "#{base_name}@#{normalized_version}"
        versioned_ref ||= if tap
          "#{tap}/#{versioned_name}"
        else
          versioned_name
        end

        installed_formula_names = Formula.installed_formula_names
        if installed_formula_names.include?(versioned_name)
          ohai "#{versioned_name} is already installed"
          return
        end

        existing_tap = Tap.installed
                          .sort_by(&:name)
                          .find { |tap| tap.formula_files_by_name.key?(versioned_name) }
        install_target = "#{existing_tap}/#{versioned_name}" if existing_tap

        versioned_formula = begin
          Formulary.factory(versioned_ref, warn: false, prefer_stub: true)
        rescue TapFormulaAmbiguityError, FormulaUnavailableError, TapFormulaUnavailableError,
               TapFormulaUnreadableError
          nil
        end

        if install_target.nil?
          install_target = if versioned_formula
            versioned_formula.full_name
          else
            current_formula = begin
              Formulary.factory(formula_input, warn: false, prefer_stub: true)
            rescue FormulaUnavailableError, TapFormulaUnavailableError, TapFormulaUnreadableError
              nil
            end

            if current_formula && current_formula.version.to_s == version_input
              if installed_formula_names.include?(current_formula.name)
                ohai "#{current_formula.full_name} is already installed"
                return
              end

              current_formula.full_name
            end
          end
        end

        # Pretend we've run a dev command to avoid making it seem like the user
        # has done so manually.
        ENV["HOMEBREW_DEV_CMD_RUN"] = "1"

        if install_target.nil?
          username = if !Homebrew::EnvConfig.no_github_api? && GitHub::API.credentials_type != :none
            begin
              GitHub.user["login"].presence
            rescue *GitHub::API::ERRORS
              nil
            end
          end
          username ||= User.current&.to_s
          username ||= ENV.fetch("USER")
          odie "Unable to determine a username for tap creation." if username.blank?

          tap = Tap.fetch("#{username}/homebrew-#{DEFAULT_TAP_REPOSITORY}")
          unless tap.installed?
            ohai "Creating #{tap.name} tap for storing versioned formulae..."
            safe_system HOMEBREW_BREW_FILE, "tap-new", "--no-git", tap.name
          end

          ohai "Extracting #{formula_input}@#{version_input} into #{tap.name}..."
          safe_system HOMEBREW_BREW_FILE, "extract", formula_input, tap.name, "--version=#{version_input}"

          install_target = "#{tap}/#{versioned_name}"

          opoo <<~EOS
            You are responsible for maintaining this #{install_target}!
            It will not receive any bugfix/security updates.
            Homebrew cannot support it for you because we cannot maintain every formula
            at every version or fix older versions in our Git history.
          EOS
        end

        ohai "Installing #{install_target}..."
        safe_system HOMEBREW_BREW_FILE, "install", install_target
      end
    end
  end
end
