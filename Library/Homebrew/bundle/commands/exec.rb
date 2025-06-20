# typed: true
# frozen_string_literal: true

require "English"
require "exceptions"
require "extend/ENV"
require "utils"
require "PATH"

module Homebrew
  module Bundle
    module Commands
      module Exec
        PATH_LIKE_ENV_REGEX = /.+#{File::PATH_SEPARATOR}/

        sig {
          params(args: String, global: T::Boolean, file: T.nilable(String), subcommand: String, services: T::Boolean,
                 check: T::Boolean).void
        }
        def self.run(*args, global: false, file: nil, subcommand: "", services: false, check: false)
          if check
            require "bundle/commands/check"
            Homebrew::Bundle::Commands::Check.run(global:, file:, quiet: true)
          end

          # Store the old environment so we can check if things were already set
          # before we start mutating it.
          old_env = ENV.to_h
          new_env = T.cast(ENV, Superenv)

          # Setup Homebrew's ENV extensions
          ENV.activate_extensions!

          command = args.first
          raise UsageError, "No command to execute was specified!" if command.blank?

          require "bundle/brewfile"
          @dsl = Brewfile.read(global:, file:)

          require "formula"
          require "formulary"

          new_env.deps = @dsl.entries.filter_map do |entry|
            next if entry.type != :brew

            Formulary.factory(entry.name)
          end

          # Allow setting all dependencies to be keg-only
          # (i.e. should be explicitly in HOMEBREW_*PATHs ahead of HOMEBREW_PREFIX)
          new_env.keg_only_deps = if ENV["HOMEBREW_BUNDLE_EXEC_ALL_KEG_ONLY_DEPS"].present?
            ENV.delete("HOMEBREW_BUNDLE_EXEC_ALL_KEG_ONLY_DEPS")
            new_env.deps
          else
            new_env.deps.select(&:keg_only?)
          end
          new_env.setup_build_environment

          # Enable compiler flag filtering
          ENV.refurbish_args

          # Set up `nodenv`, `pyenv` and `rbenv` if present.
          env_formulae = %w[nodenv pyenv rbenv]
          new_env.deps.each do |dep|
            dep_name = dep.name
            next unless env_formulae.include?(dep_name)

            dep_root = ENV.fetch("HOMEBREW_#{dep_name.upcase}_ROOT", "#{Dir.home}/.#{dep_name}")
            ENV.prepend_path "PATH", Pathname.new(dep_root)/"shims"
          end

          # Setup pkgconf, if needed, to help locate packages
          Bundle.prepend_pkgconf_path_if_needed!

          # For commands which aren't either absolute or relative
          # Add the command directory to PATH, since it may get blown away by superenv
          if command.exclude?("/") && (which_command = which(command)).present?
            ENV.prepend_path "PATH", which_command.dirname.to_s
          end

          # Replace the formula versions from the environment variables
          new_env.deps.each do |formula|
            formula_name = formula.name
            formula_version = Bundle.formula_versions_from_env(formula_name)
            next unless formula_version

            ENV.each do |key, value|
              opt = %r{/opt/#{formula_name}([/:$])}
              next unless value.match(opt)

              cellar = "/Cellar/#{formula_name}/#{formula_version}\\1"

              # Look for PATH-like environment variables
              ENV[key] = if key.include?("PATH") && value.match?(PATH_LIKE_ENV_REGEX)
                rejected_opts = []
                path = PATH.new(ENV.fetch("PATH"))
                           .reject do |path_value|
                  if path_value.match?(opt)
                    rejected_opts << path_value
                    true
                  else
                    false
                  end
                end
                rejected_opts.each do |path_value|
                  path.prepend(path_value.gsub(opt, cellar))
                end
                path.to_s
              else
                value.gsub(opt, cellar)
              end
            end
          end

          # Ensure brew bundle exec/sh/env commands have access to other tools in the PATH
          if (homebrew_path = ENV.fetch("HOMEBREW_PATH", nil))
            ENV.append_path "PATH", homebrew_path
          end

          # For commands which aren't either absolute or relative
          raise "command was not found in your PATH: #{command}" if command.exclude?("/") && which(command).nil?

          %w[HOMEBREW_TEMP TMPDIR HOMEBREW_TMPDIR].each do |var|
            value = ENV.fetch(var, nil)
            next if value.blank?
            next if File.writable?(value)

            ENV.delete(var)
          end

          ENV.each do |key, value|
            # Look for PATH-like environment variables
            next if key.exclude?("PATH") || !value.match?(PATH_LIKE_ENV_REGEX)

            # Exclude Homebrew shims from the PATH as they don't work
            # without all Homebrew environment variables and can interfere with
            # non-Homebrew builds.
            ENV[key] = PATH.new(value)
                           .reject do |path_value|
              path_value.include?("/Homebrew/shims/")
            end.to_s
          end

          if subcommand == "env"
            ENV.sort.each do |key, value|
              # Skip exporting Homebrew internal variables that won't be used by other tools.
              # Those Homebrew needs have already been set to global constants and/or are exported again later.
              # Setting these globally can interfere with nested Homebrew invocations/environments.
              if key.start_with?("HOMEBREW_", "PORTABLE_RUBY_")
                ENV.delete(key)
                next
              end

              # No need to export empty values.
              next if value.blank?

              # Skip exporting things that were the same in the old environment.
              old_value = old_env[key]
              next if old_value == value

              # Look for PATH-like environment variables
              if key.include?("PATH") && value.match?(PATH_LIKE_ENV_REGEX)
                old_values = old_value.to_s.split(File::PATH_SEPARATOR)
                path = PATH.new(value)
                           .reject do |path_value|
                  # Exclude existing/old values as they've already been exported.
                  old_values.include?(path_value)
                end
                next if path.blank?

                puts "export #{key}=\"#{Utils::Shell.sh_quote(path.to_s)}:${#{key}:-}\""
              else
                puts "export #{key}=\"#{Utils::Shell.sh_quote(value)}\""
              end
            end
            return
          elsif subcommand == "sh"
            preferred_path = Utils::Shell.preferred_path(default: "/bin/bash")
            notice = unless Homebrew::EnvConfig.no_env_hints?
              <<~EOS
                Your shell has been configured to use a build environment from your `Brewfile`.
                This should help you build stuff.
                Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).
                When done, type `exit`.
              EOS
            end
            ENV["HOMEBREW_FORCE_API_AUTO_UPDATE"] = nil
            args = [Utils::Shell.shell_with_prompt("brew bundle", preferred_path:, notice:)]
          end

          if services
            require "bundle/brew_services"

            exit_code = T.let(0, Integer)
            run_services(@dsl.entries) do
              Kernel.system(*args)
              if (system_exit_code = $CHILD_STATUS&.exitstatus)
                exit_code = system_exit_code
              end
            end
            exit!(exit_code)
          else
            exec(*args)
          end
        end

        sig {
          params(
            entries: T::Array[Homebrew::Bundle::Dsl::Entry],
            _block:  T.proc.params(
              entry:                Homebrew::Bundle::Dsl::Entry,
              info:                 T::Hash[String, T.untyped],
              service_file:         Pathname,
              conflicting_services: T::Array[T::Hash[String, T.untyped]],
            ).void,
          ).void
        }
        private_class_method def self.map_service_info(entries, &_block)
          entries_formulae = entries.filter_map do |entry|
            next if entry.type != :brew

            formula = Formula[entry.name]
            next unless formula.any_version_installed?

            [entry, formula]
          end.to_h

          return if entries_formulae.empty?

          conflicts = entries_formulae.to_h do |entry, formula|
            [
              entry,
              (
                formula.versioned_formulae_names +
                  formula.conflicts.map(&:name) +
                  Array(entry.options[:conflicts_with])
              ).uniq,
            ]
          end

          # The formula + everything that could possible conflict with the service
          names_to_query = entries_formulae.flat_map do |entry, formula|
            [
              formula.name,
              *conflicts.fetch(entry),
            ]
          end

          # We parse from a command invocation so that brew wrappers can invoke special actions
          # for the elevated nature of `brew services`
          services_info = JSON.parse(
            Utils.safe_popen_read(HOMEBREW_BREW_FILE, "services", "info", "--json", *names_to_query),
          )

          entries_formulae.filter_map do |entry, formula|
            service_file = Bundle::BrewServices.versioned_service_file(entry.name)

            unless service_file&.file?
              prefix = formula.any_installed_prefix
              next if prefix.nil?

              service_file = if Homebrew::Services::System.launchctl?
                prefix/"#{formula.plist_name}.plist"
              else
                prefix/"#{formula.service_name}.service"
              end
            end

            next unless service_file.file?

            info = services_info.find { |candidate| candidate["name"] == formula.name }
            conflicting_services = services_info.select do |candidate|
              next unless candidate["running"]

              conflicts.fetch(entry).include?(candidate["name"])
            end

            raise "Failed to get service info for #{entry.name}" if info.nil?

            yield entry, info, service_file, conflicting_services
          end
        end

        sig { params(entries: T::Array[Homebrew::Bundle::Dsl::Entry], _block: T.nilable(T.proc.void)).void }
        private_class_method def self.run_services(entries, &_block)
          entries_to_stop = []
          services_to_restart = []

          map_service_info(entries) do |entry, info, service_file, conflicting_services|
            # Don't restart if already running this version
            loaded_file = Pathname.new(info["loaded_file"].to_s)
            next if info["running"] && loaded_file.file? && loaded_file.realpath == service_file.realpath

            if info["running"] && !Bundle::BrewServices.stop(info["name"], keep: true)
              opoo "Failed to stop #{info["name"]} service"
            end

            conflicting_services.each do |conflict|
              if Bundle::BrewServices.stop(conflict["name"], keep: true)
                services_to_restart << conflict["name"] if conflict["registered"]
              else
                opoo "Failed to stop #{conflict["name"]} service"
              end
            end

            unless Bundle::BrewServices.run(info["name"], file: service_file)
              opoo "Failed to start #{info["name"]} service"
            end

            entries_to_stop << entry
          end

          return unless block_given?

          begin
            yield
          ensure
            # Do a full re-evaluation of services instead state has changed
            stop_services(entries_to_stop)

            services_to_restart.each do |service|
              next if Bundle::BrewServices.run(service)

              opoo "Failed to restart #{service} service"
            end
          end
        end

        sig { params(entries: T::Array[Homebrew::Bundle::Dsl::Entry]).void }
        private_class_method def self.stop_services(entries)
          map_service_info(entries) do |_, info, _, _|
            next unless info["loaded"]

            # Try avoid services not started by `brew bundle services`
            next if Homebrew::Services::System.launchctl? && info["registered"]

            if info["running"] && !Bundle::BrewServices.stop(info["name"], keep: true)
              opoo "Failed to stop #{info["name"]} service"
            end
          end
        end
      end
    end
  end
end
