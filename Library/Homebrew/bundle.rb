# typed: strict
# frozen_string_literal: true

require "English"

module Homebrew
  module Bundle
    class << self
      sig { params(args_upgrade_formula: T.nilable(String)).void }
      def upgrade_formulae=(args_upgrade_formula)
        @upgrade_formulae = args_upgrade_formula.to_s.split(",")
      end

      sig { returns(T::Array[String]) }
      def upgrade_formulae
        @upgrade_formulae || []
      end

      sig { params(cmd: T.any(String, Pathname), args: T.anything, verbose: T::Boolean).returns(T::Boolean) }
      def system(cmd, *args, verbose: false)
        return super cmd, *args if verbose

        logs = []
        success = T.let(false, T::Boolean)
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

      sig { params(args: T.anything, verbose: T::Boolean).returns(T::Boolean) }
      def brew(*args, verbose: false)
        system(HOMEBREW_BREW_FILE, *args, verbose:)
      end

      sig { returns(T::Boolean) }
      def mas_installed?
        @mas_installed ||= which_formula?("mas")
      end

      sig { returns(T::Boolean) }
      def vscode_installed?
        @vscode_installed ||= which_vscode.present?
      end

      sig { returns(T.nilable(Pathname)) }
      def which_vscode
        @which_vscode ||= which("code", ORIGINAL_PATHS)
        @which_vscode ||= which("codium", ORIGINAL_PATHS)
        @which_vscode ||= which("cursor", ORIGINAL_PATHS)
        @which_vscode ||= which("code-insiders", ORIGINAL_PATHS)
      end

      sig { returns(T::Boolean) }
      def whalebrew_installed?
        @whalebrew_installed ||= which_formula?("whalebrew")
      end

      sig { returns(T::Boolean) }
      def cask_installed?
        @cask_installed ||= File.directory?("#{HOMEBREW_PREFIX}/Caskroom") &&
                            (File.directory?("#{HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-cask") ||
                             !Homebrew::EnvConfig.no_install_from_api?)
      end

      sig { params(name: String).returns(T::Boolean) }
      def which_formula?(name)
        formula = Formulary.factory(name)
        ENV["PATH"] = "#{formula.opt_bin}:#{ENV.fetch("PATH", nil)}" if formula.any_version_installed?
        which(name).present?
      end

      sig { params(block: T.proc.returns(T.anything)).returns(T.untyped) }
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

      sig { params(formula_name: String).returns(T.nilable(String)) }
      def formula_versions_from_env(formula_name)
        @formula_versions_from_env ||= begin
          formula_versions = {}

          ENV.each do |key, value|
            match = key.match(/^HOMEBREW_BUNDLE_FORMULA_VERSION_(.+)$/)
            next if match.blank?

            env_formula_name = match[1]
            next if env_formula_name.blank?

            ENV.delete(key)
            formula_versions[env_formula_name] = value
          end

          formula_versions
        end

        # Fix up formula name for a valid environment variable name.
        formula_env_name = formula_name.upcase
                                       .gsub("@", "AT")
                                       .tr("+", "X")
                                       .tr("-", "_")

        @formula_versions_from_env[formula_env_name]
      end

      sig { void }
      def prepend_pkgconf_path_if_needed!; end

      sig { void }
      def reset!
        @mas_installed = T.let(nil, T.nilable(T::Boolean))
        @vscode_installed = T.let(nil, T.nilable(T::Boolean))
        @which_vscode = T.let(nil, T.nilable(String))
        @whalebrew_installed = T.let(nil, T.nilable(T::Boolean))
        @cask_installed = T.let(nil, T.nilable(T::Boolean))
        @formula_versions_from_env = T.let(nil, T.nilable(T::Hash[String, String]))
        @upgrade_formulae = T.let(nil, T.nilable(T::Array[String]))
      end
    end
  end
end

require "extend/os/bundle/bundle"
