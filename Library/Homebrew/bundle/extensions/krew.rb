# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"
require "yaml"

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
          @indexes_updated = T.let(nil, T.nilable(T::Boolean))
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

        sig { override.params(executable: Pathname).returns(T::Hash[String, String]) }
        def package_manager_env(executable)
          { "PATH" => "#{executable.dirname}:#{ORIGINAL_PATHS.join(":")}" }
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if package_manager_installed?
            with_package_manager_env do |krew|
              parse_plugin_list(command_output(krew, args: ["list"]))
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
            Bundle.system(krew.to_s, package_installed?(name) ? "upgrade" : "install", name, verbose:)
          end
        end

        sig { override.returns(T::Array[String]) }
        def installed_packages
          @installed_packages ||= packages.dup
        end

        sig {
          override.params(name: String, with: T.nilable(T::Array[String]), source: T.nilable(String)).returns(T::Boolean)
        }
        def package_outdated?(name, with: nil, source: nil)
          with_package_manager_env do |krew|
            unless @indexes_updated
              command_output(krew, args: ["update"])
              @indexes_updated = true
            end

            receipt = YAML.safe_load_file(File.join(ENV["KREW_ROOT"].presence || "#{Dir.home}/.krew",
                                                    "receipts", "#{Pathname.new(name).basename}.yaml"))
            spec = receipt["spec"] if receipt.is_a?(Hash)
            installed = spec["version"] if spec.is_a?(Hash)
            latest = command_output(krew, args: ["info", name])[/^VERSION: (\S+)$/, 1]
            if !installed.is_a?(String) || installed.blank? || latest.blank?
              raise "Invalid Krew version for #{name}"
            end

            Version.new(latest) > Version.new(installed)
          end
        end

        sig { params(output: String).returns(T::Array[String]) }
        def parse_plugin_list(output)
          # Krew prints only plugin names when stdout is piped.
          names = output.each_line(chomp: true).reject(&:empty?)
          if names.any? { |name| name.match?(/[[:space:]]/) }
            raise "Invalid Krew inventory: plugin names cannot contain whitespace"
          end

          names.uniq
        end
        private :parse_plugin_list

        sig { override.params(name: String, executable: Pathname).returns(T::Boolean) }
        def uninstall_package!(name, executable: Pathname.new(""))
          Bundle.system(executable.to_s, "uninstall", name, verbose: false)
        end
      end
    end
  end
end
