# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class Krew < Extension
      class << self
        sig { override.returns(Symbol) }
        def type = :krew

        sig { override.returns(String) }
        def check_label = "Krew Plugin"

        sig { override.returns(String) }
        def banner_name = "Krew plugins"

        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[String]))
          @installed_packages = T.let(nil, T.nilable(T::Array[String]))
          @package_manager_executable = T.let(nil, T.nilable(Pathname))
        end

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          banner_name
        end

        sig { override.returns(T.nilable(Pathname)) }
        def package_manager_executable
          @package_manager_executable ||= T.let(which("kubectl-krew", ORIGINAL_PATHS), T.nilable(Pathname))
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if package_manager_installed?
            with_package_manager_env do |krew|
              parse_plugin_list(`#{krew} list 2>/dev/null`)
            end
          else
            []
          end
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

          with_package_manager_env do |krew|
            Bundle.system(krew.to_s, "install", name, verbose:)
          end
        end

        sig { override.returns(T::Array[String]) }
        def installed_packages
          installed_packages = @installed_packages
          return installed_packages if installed_packages

          @installed_packages = packages.dup
        end

        sig { params(output: String).returns(T::Array[String]) }
        def parse_plugin_list(output)
          output.lines.filter_map do |line|
            line = line.strip
            next if line.empty?

            name = line.split(/\s+/).first
            name.presence
          end.uniq
        end
        private :parse_plugin_list

        sig { override.params(name: String, executable: Pathname).void }
        def uninstall_package!(name, executable: Pathname.new(""))
          Bundle.system(executable.to_s, "uninstall", name, verbose: false)
        end
      end
    end
  end
end
