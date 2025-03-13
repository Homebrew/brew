# typed: false
# frozen_string_literal: true

require "exceptions"
require "extend/ENV"
require "utils"
require "PATH"

module Bundle
  module Commands
    module Exec
      module_function

      # Homebrew's global environment variables that we don't want to leak into
      # the `brew bundle exec` environment.
      HOMEBREW_ENV_CLEANUP = %w[
        HOMEBREW_HELP_MESSAGE
        HOMEBREW_API_DEFAULT_DOMAIN
        HOMEBREW_BOTTLE_DEFAULT_DOMAIN
        HOMEBREW_BREW_DEFAULT_GIT_REMOTE
        HOMEBREW_CORE_DEFAULT_GIT_REMOTE
        HOMEBREW_DEFAULT_CACHE
        HOMEBREW_DEFAULT_LOGS
        HOMEBREW_DEFAULT_TEMP
        HOMEBREW_REQUIRED_RUBY_VERSION
        HOMEBREW_PRODUCT
        HOMEBREW_SYSTEM
        HOMEBREW_PROCESSOR
        HOMEBREW_PHYSICAL_PROCESSOR
        HOMEBREW_BREWED_CURL_PATH
        HOMEBREW_USER_AGENT_CURL
        HOMEBREW_USER_AGENT
        HOMEBREW_GENERIC_DEFAULT_PREFIX
        HOMEBREW_GENERIC_DEFAULT_REPOSITORY
        HOMEBREW_DEFAULT_PREFIX
        HOMEBREW_DEFAULT_REPOSITORY
        HOMEBREW_AUTO_UPDATE_COMMAND
        HOMEBREW_BREW_GIT_REMOTE
        HOMEBREW_COMMAND_DEPTH
        HOMEBREW_CORE_GIT_REMOTE
        HOMEBREW_MACOS_VERSION_NUMERIC
        HOMEBREW_MINIMUM_GIT_VERSION
        HOMEBREW_MACOS_NEWEST_UNSUPPORTED
        HOMEBREW_MACOS_OLDEST_SUPPORTED
        HOMEBREW_MACOS_OLDEST_ALLOWED
        HOMEBREW_GITHUB_PACKAGES_AUTH
      ].freeze

      PATH_LIKE_ENV_REGEX = /.+#{File::PATH_SEPARATOR}/

      def run(*args, global: false, file: nil, subcommand: "")
        # Cleanup Homebrew's global environment
        HOMEBREW_ENV_CLEANUP.each { |key| ENV.delete(key) }

        # Setup Homebrew's ENV extensions
        ENV.activate_extensions!
        raise UsageError, "No command to execute was specified!" if args.blank?

        command = args.first

        # For commands which aren't either absolute or relative
        if command.exclude? "/"
          # Save the command path, since this will be blown away by superenv
          command_path = which(command)
          raise "command was not found in your PATH: #{command}" if command_path.blank?

          command_path = command_path.dirname.to_s
        end

        @dsl = Brewfile.read(global:, file:)

        require "formula"
        require "formulary"

        ENV.deps = @dsl.entries.filter_map do |entry|
          next if entry.type != :brew

          Formulary.factory(entry.name)
        end

        # Allow setting all dependencies to be keg-only
        # (i.e. should be explicitly in HOMEBREW_*PATHs ahead of HOMEBREW_PREFIX)
        ENV.keg_only_deps = if ENV["HOMEBREW_BUNDLE_EXEC_ALL_KEG_ONLY_DEPS"].present?
          ENV.delete("HOMEBREW_BUNDLE_EXEC_ALL_KEG_ONLY_DEPS")
          ENV.deps
        else
          ENV.deps.select(&:keg_only?)
        end
        ENV.setup_build_environment

        # Enable compiler flag filtering
        ENV.refurbish_args

        # Set up `nodenv`, `pyenv` and `rbenv` if present.
        env_formulae = %w[nodenv pyenv rbenv]
        ENV.deps.each do |dep|
          dep_name = dep.name
          next unless env_formulae.include?(dep_name)

          dep_root = ENV.fetch("HOMEBREW_#{dep_name.upcase}_ROOT", "#{Dir.home}/.#{dep_name}")
          ENV.prepend_path "PATH", Pathname.new(dep_root)/"shims"
        end

        # Setup pkg-config, if present, to help locate packages
        # Only need this on Linux as Homebrew provides a shim on macOS
        if OS.linux? && (pkgconf = Formulary.factory("pkgconf")) && pkgconf.any_version_installed?
          ENV.prepend_path "PATH", pkgconf.opt_bin.to_s
        end

        # Ensure the Ruby path we saved goes before anything else, if the command was in the PATH
        ENV.prepend_path "PATH", command_path if command_path.present?

        # Replace the formula versions from the environment variables
        formula_versions = {}
        ENV.each do |key, value|
          match = key.match(/^HOMEBREW_BUNDLE_EXEC_FORMULA_VERSION_(.+)$/)
          next if match.blank?

          formula_name = match[1]
          next if formula_name.blank?

          ENV.delete(key)
          formula_versions[formula_name.downcase] = value
        end
        formula_versions.each do |formula_name, formula_version|
          ENV.each do |key, value|
            opt = %r{/opt/#{formula_name}([/:$])}
            next unless value.match(opt)

            cellar = "/Cellar/#{formula_name}/#{formula_version}\\1"

            # Look for PATH-like environment variables
            ENV[key] = if key.include?("PATH") && value.match?(PATH_LIKE_ENV_REGEX)
              rejected_opts = []
              path = PATH.new(ENV.fetch("PATH"))
                         .reject do |value|
                rejected_opts << value if value.match?(opt)
              end
              rejected_opts.each do |value|
                path.prepend(value.gsub(opt, cellar))
              end
              path.to_s
            else
              value.gsub(opt, cellar)
            end
          end
        end

        # Ensure brew bundle sh/env commands have access to other tools in the PATH
        if ["sh", "env"].include?(subcommand) && (homebrew_path = ENV.fetch("HOMEBREW_PATH", nil))
          ENV.append_path "PATH", homebrew_path
        end

        if subcommand == "env"
          ENV.each do |key, value|
            puts "export #{key}=\"#{value}\""
          end
          return
        end

        exec(*args)
      end
    end
  end
end
