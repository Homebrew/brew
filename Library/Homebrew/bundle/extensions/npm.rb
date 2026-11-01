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

        sig { override.params(executable: Pathname).returns(T::Hash[String, String]) }
        def package_manager_env(executable)
          { "PATH" => "#{executable.dirname}:#{ORIGINAL_PATHS.join(":")}" }
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
              listed_package_names(npm)
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
          @installed_packages ||= packages.dup
        end

        sig { returns(T::Array[String]) }
        def outdated_packages
          outdated_packages = @outdated_packages
          return outdated_packages if outdated_packages
          return [] unless (npm = package_manager_executable)

          @outdated_packages = with_env(package_manager_env(npm)) do
            outdated_package_names(npm)
          end
        end

        sig { override.params(name: String, executable: Pathname).returns(T::Boolean) }
        def uninstall_package!(name, executable: Pathname.new(""))
          Bundle.system(executable.to_s, "uninstall", "-g", name, verbose: false)
        end

        sig { params(npm: Pathname, command: String).returns([SystemCommand::Result, T::Hash[String, Object]]) }
        def inventory_json(npm, command)
          result = SystemCommand.run(npm, args: [command, "-g", "--depth=0", "--json"], print_stderr: false)
          result.assert_success! unless [0, 1].include?(result.exit_status)

          begin
            json = JSON.parse(result.stdout)
          rescue JSON::ParserError
            result.assert_success!
            raise "Invalid npm #{command} inventory: expected JSON"
          end

          unless json.is_a?(Hash)
            result.assert_success!
            raise "Invalid npm #{command} inventory: unexpected JSON structure"
          end

          [result, json]
        end
        private :inventory_json

        sig { params(npm: Pathname).returns(T::Array[String]) }
        def listed_package_names(npm)
          result, json = inventory_json(npm, "list")
          dependencies = json.fetch("dependencies", {})
          valid = if result.exit_status == 1
            error = json["error"]
            json["dependencies"].is_a?(Hash) && error.is_a?(Hash) && error["code"] == "ELSPROBLEMS"
          else
            !json.key?("error")
          end

          if !dependencies.is_a?(Hash) || !valid
            result.assert_success!
            raise "Invalid npm list inventory: unexpected JSON structure"
          end

          dependencies = dependencies.reject do |_, metadata|
            metadata.is_a?(Hash) && metadata["missing"] == true
          end

          dependencies.keys.reject { |name| name == "npm" }
        end
        private :listed_package_names

        sig { params(npm: Pathname).returns(T::Array[String]) }
        def outdated_package_names(npm)
          result, json = inventory_json(npm, "outdated")
          result.assert_success! if json.empty?

          valid = json.each_value.all? do |value|
            records = value.is_a?(Array) ? value : [value]
            next false if records.empty?

            records.all? do |record|
              next false unless record.is_a?(Hash)

              record.values_at("wanted", "latest").all?(String)
            end
          end

          unless valid
            result.assert_success!
            raise "Invalid npm outdated inventory: unexpected JSON structure"
          end

          json.keys.reject { |name| name == "npm" }
        end
        private :outdated_package_names
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
