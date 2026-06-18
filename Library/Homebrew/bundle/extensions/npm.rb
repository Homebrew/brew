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

        sig { override.returns(String) }
        def package_manager_name
          "node"
        end

        sig { override.returns(T.nilable(Pathname)) }
        def package_manager_executable
          which("npm", ORIGINAL_PATHS)
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if (npm = package_manager_executable) &&
                         (!npm.to_s.start_with?("/") || npm.exist?)
            with_env(package_manager_env(npm)) do
              parse_package_list(`#{npm} list -g --depth=0 --json 2>/dev/null`)
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

          npm = package_manager_executable!

          Bundle.system(npm.to_s, "install", *Language::Node.npm_install_security_args, "-g", name, verbose:)
        end

        sig { override.returns(T::Array[String]) }
        def installed_packages
          installed_packages = @installed_packages
          return installed_packages if installed_packages

          @installed_packages = packages.dup
        end

        sig { override.params(name: String, executable: Pathname).void }
        def uninstall_package!(name, executable: Pathname.new(""))
          Bundle.system(executable.to_s, "uninstall", "-g", name, verbose: false)
        end

        sig { params(output: String).returns(T::Array[String]) }
        def parse_package_list(output)
          return [] if output.blank?

          json = JSON.parse(output)
          deps = json.fetch("dependencies", {})
          deps.keys.reject { |name| name == "npm" }
        rescue JSON::ParserError
          []
        end
        private :parse_package_list
      end
    end
  end
end
