# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"
require "language/node"

module Homebrew
  module Bundle
    class Npm < Extension
      class << self
        sig { override.returns(Symbol) }
        def type = :npm

        sig { override.returns(String) }
        def check_label = "npm Package"

        sig { override.returns(String) }
        def banner_name = "npm packages"

        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[String]))
          @installed_packages = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          banner_name
        end

        BOOTSTRAP_RUNTIME = T.let("node", String)
        BOOTSTRAP_PACKAGE_MANAGER = T.let("pnpm", String)
        BOOTSTRAP_FORMULAE = T.let([BOOTSTRAP_RUNTIME, BOOTSTRAP_PACKAGE_MANAGER].freeze, T::Array[String])

        sig { override.returns(String) }
        def package_manager_name
          BOOTSTRAP_PACKAGE_MANAGER
        end

        sig { override.returns(T.nilable(Pathname)) }
        def package_manager_executable
          which("pnpm", ORIGINAL_PATHS) || which("npm", ORIGINAL_PATHS)
        end

        sig {
          override.params(
            name:       String,
            with:       T.nilable(T::Array[String]),
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            _options:   Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def preinstall!(name, with: nil, no_upgrade: false, verbose: false, **_options)
          _ = no_upgrade

          unless package_manager_installed?
            if verbose
              puts "Installing #{BOOTSTRAP_RUNTIME} (runtime) and #{BOOTSTRAP_PACKAGE_MANAGER}. " \
                   "They are not currently installed."
            end
            Bundle.system(HOMEBREW_BREW_FILE, "install", "--formula", *BOOTSTRAP_FORMULAE, verbose:)
            formula_versions_from_env = T.let(
              Bundle.formula_versions_from_env_cache,
              T.nilable(T::Hash[String, String]),
            )
            upgrade_formulae = Bundle.upgrade_formulae
            Bundle.reset!
            Bundle.formula_versions_from_env_cache = formula_versions_from_env
            Bundle.upgrade_formulae = upgrade_formulae.join(",")
            unless package_manager_installed?
              raise "Unable to install #{name} #{package_description}. " \
                    "Node.js and pnpm installation failed."
            end
          end

          if package_installed?(name, with:)
            puts "Skipping install of #{name} #{package_description}. It is already installed." if verbose
            return false
          end

          true
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if (executable = package_manager_executable) &&
                         (!executable.to_s.start_with?("/") || executable.exist?)
            with_env(package_manager_env(executable)) do
              parse_package_list(`#{executable} list -g --depth=0 --json 2>/dev/null`)
            end
          end
          return [] if @packages.nil?

          @packages
        end

        sig {
          override.params(
            name:    String,
            with:    T.nilable(T::Array[String]),
            verbose: T::Boolean,
          ).returns(T::Boolean)
        }
        def install_package!(name, with: nil, verbose: false)
          _ = with

          executable = package_manager_executable!

          if pnpm_executable?(executable)
            Bundle.system(executable.to_s, "add", "-g", name, verbose:)
          else
            Bundle.system(executable.to_s, "install", *Language::Node.npm_install_security_args, "-g", name, verbose:)
          end
        end

        sig { override.returns(T::Array[String]) }
        def installed_packages
          installed_packages = @installed_packages
          return installed_packages if installed_packages

          @installed_packages = packages.dup
        end

        sig { override.params(name: String, executable: Pathname).void }
        def uninstall_package!(name, executable: Pathname.new(""))
          if pnpm_executable?(executable)
            Bundle.system(executable.to_s, "remove", "-g", name, verbose: false)
          else
            Bundle.system(executable.to_s, "uninstall", "-g", name, verbose: false)
          end
        end

        sig { params(output: String).returns(T::Array[String]) }
        def parse_package_list(output)
          return [] if output.blank?

          json = JSON.parse(output)
          package_entries = json.is_a?(Array) ? json : [json]
          package_entries.flat_map do |package|
            next [] unless package.is_a?(Hash)

            deps = package.fetch("dependencies", {})
            deps.keys.reject { |package_name| %w[npm pnpm].include?(package_name) }
          end
        rescue JSON::ParserError
          []
        end
        private :parse_package_list

        sig { params(executable: Pathname).returns(T::Boolean) }
        def pnpm_executable?(executable)
          executable.basename.to_s == "pnpm"
        end
        private :pnpm_executable?
      end
    end
  end
end
