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
          @outdated_packages = T.let(nil, T.nilable(T::Array[String]))
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

        sig { override.params(name: String, _options: Homebrew::Bundle::EntryOptions).returns(String) }
        def install_verb(name = "", _options = {})
          package_installed?(name) ? "Upgrading" : "Installing"
        end

        sig {
          override.params(
            name:       String,
            with:       T.nilable(T::Array[String]),
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            options:    Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def preinstall!(name, with: nil, no_upgrade: false, verbose: false, **options)
          return true if !no_upgrade && package_installed?(name, with:) && outdated_packages.include?(name)

          super
        end

        sig {
          override.params(
            name:       String,
            with:       T.nilable(T::Array[String]),
            preinstall: T::Boolean,
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            force:      T::Boolean,
            options:    Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def install!(name, with: nil, preinstall: true, no_upgrade: false, verbose: false, force: false, **options)
          return super if !preinstall || !package_installed?(name, with:)

          puts "Upgrading #{name} #{package_description}. It is installed but not up-to-date." if verbose
          install_package!(name, with:, verbose:)
        end

        sig { override.params(_name: String, _options: Homebrew::Bundle::EntryOptions).returns(T::Boolean) }
        def batch_installable?(_name, _options = {})
          true
        end

        sig { override.params(entries: T::Array[Dsl::Entry], verbose: T::Boolean).returns(T::Boolean) }
        def install_batch!(entries, verbose: false)
          Bundle.system(package_manager_executable!.to_s, "install", *Language::Node.npm_install_security_args,
                        "-g", *entries.map(&:name), verbose:)
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if (npm = package_manager_executable) &&
                         (!npm.to_s.start_with?("/") || npm.exist?)
            with_env(package_manager_env(npm)) do
              parse_package_list(Utils.popen_read_text(npm, "list", "-g", "--depth=0", "--json", err: File::NULL))
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

        sig { returns(T::Array[String]) }
        def outdated_packages
          outdated_packages = @outdated_packages
          return outdated_packages if outdated_packages
          return [] unless (npm = package_manager_executable)

          @outdated_packages = with_env(package_manager_env(npm)) do
            JSON.parse(Utils.popen_read_text(npm, "outdated", "-g", "--depth=0", "--json", err: File::NULL))
                .keys.reject { |name| name == "npm" }
          end
        rescue JSON::ParserError
          @outdated_packages = []
        end

        sig { override.params(name: String, executable: Pathname).returns(T::Boolean) }
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

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(String) }
      def failure_reason(package, no_upgrade:)
        return super if no_upgrade || !self.class.package_installed?(self.class.dump_name(package))

        "#{self.class.check_label} #{self.class.dump_name(package)} needs to be upgraded."
      end

      sig { override.params(package: Object, no_upgrade: T::Boolean).returns(T::Boolean) }
      def installed_and_up_to_date?(package, no_upgrade: false)
        super && (no_upgrade || self.class.outdated_packages.exclude?(self.class.dump_name(package)))
      end
    end
  end
end
