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
      def cask_installed?
        @cask_installed ||= File.directory?("#{HOMEBREW_PREFIX}/Caskroom") &&
                            (File.directory?("#{HOMEBREW_LIBRARY}/Taps/homebrew/homebrew-cask") ||
                             !Homebrew::EnvConfig.no_install_from_api?)
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

      sig { returns(T.nilable(T::Hash[String, String])) }
      def formula_versions_from_env_cache
        @formula_versions_from_env
      end

      sig { params(formula_versions: T.nilable(T::Hash[String, String])).void }
      def formula_versions_from_env_cache=(formula_versions)
        @formula_versions_from_env = formula_versions
      end

      sig { void }
      def prepend_pkgconf_path_if_needed!; end

      sig { void }
      def reset!
        @cask_installed = T.let(nil, T.nilable(T::Boolean))
        @formula_versions_from_env = T.let(nil, T.nilable(T::Hash[String, String]))
        @upgrade_formulae = T.let(nil, T.nilable(T::Array[String]))
      end

      # Marks Brewfile formulae as installed_on_request to prevent autoremove
      # from removing them when their dependents are uninstalled.
      sig { params(entries: T::Array[Dsl::Entry]).void }
      def mark_as_installed_on_request!(entries)
        return if entries.empty?

        require "tab"

        installed_formulae = Formula.installed_formula_names
        return if installed_formulae.empty?

        use_brew_tab = T.let(false, T::Boolean)

        formulae_to_update = entries.filter_map do |entry|
          next if entry.type != :brew

          name = entry.name
          next if installed_formulae.exclude?(name)

          tab = Tab.for_name(name)
          next if tab.tabfile.blank? || !tab.tabfile.exist?
          next if tab.installed_on_request

          next name if use_brew_tab

          tab.installed_on_request = true

          begin
            tab.write
            nil
          rescue Errno::EACCES
            # Some wrappers might treat `brew bundle` with lower permissions due to its execution of user code.
            # Running through `brew tab` ensures proper privilege escalation by going through the wrapper again.
            use_brew_tab = true
            name
          end
        end

        brew "tab", "--installed-on-request", *formulae_to_update if use_brew_tab
      end
    end
  end
end

require "extend/os/bundle/bundle"
