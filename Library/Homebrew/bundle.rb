# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "English"

module Homebrew
  module Bundle
    class << self
      def system(cmd, *args, verbose: false)
        return super cmd, *args if verbose

        logs = []
        success = T.let(nil, T.nilable(T::Boolean))
        IO.popen([cmd, *args], err: [:child, :out]) do |pipe|
          while (buf = pipe.gets)
            logs << buf
          end
          Process.wait(pipe.pid)
          success = $CHILD_STATUS.success?
          pipe.close
        end
        puts logs.join unless success
        success
      end

      def brew(*args, verbose: false)
        system(HOMEBREW_BREW_FILE, *args, verbose:)
      end

      def mas_installed?
        @mas_installed ||= which_formula("mas")
      end

      def vscode_installed?
        @vscode_installed ||= which_vscode.present?
      end

      def which_vscode
        @which_vscode ||= which("code", ORIGINAL_PATHS)
        @which_vscode ||= which("codium", ORIGINAL_PATHS)
        @which_vscode ||= which("cursor", ORIGINAL_PATHS)
        @which_vscode ||= which("code-insiders", ORIGINAL_PATHS)
      end

      def whalebrew_installed?
        @whalebrew_installed ||= which_formula("whalebrew")
      end

      def cask_installed?
        @cask_installed ||= File.directory?("#{HOMEBREW_PREFIX}/Caskroom") &&
                            (File.directory?("#{HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-cask") ||
                             !Homebrew::EnvConfig.no_install_from_api?)
      end

      def which_formula(name)
        formula = Formulary.factory(name)
        ENV["PATH"] = "#{formula.opt_bin}:#{ENV.fetch("PATH", nil)}" if formula.any_version_installed?
        which(name).present?
      end

      def exchange_uid_if_needed!(&block)
        euid = Process.euid
        uid = Process.uid
        return yield if euid == uid

        old_euid = euid
        process_reexchangeable = Process::UID.re_exchangeable?
        if process_reexchangeable
          Process::UID.re_exchange
        else
          Process::Sys.seteuid(uid)
        end

        home = T.must(Etc.getpwuid(Process.uid)).dir
        return_value = with_env("HOME" => home, &block)

        if process_reexchangeable
          Process::UID.re_exchange
        else
          Process::Sys.seteuid(old_euid)
        end

        return_value
      end

      def formula_versions_from_env
        @formula_versions_from_env ||= begin
          formula_versions = {}

          ENV.each do |key, value|
            match = key.match(/^HOMEBREW_BUNDLE_EXEC_FORMULA_VERSION_(.+)$/)
            next if match.blank?

            formula_name = match[1]
            next if formula_name.blank?

            ENV.delete(key)
            formula_versions[formula_name.downcase] = value
          end

          formula_versions
        end
      end

      sig { void }
      def reset!
        @mas_installed = nil
        @vscode_installed = nil
        @whalebrew_installed = nil
        @cask_installed = nil
        @formula_versions_from_env = nil
      end
    end
  end
end

require "extend/os/bundle/bundle"
