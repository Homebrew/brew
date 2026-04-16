# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class Cargo < Extension
      PACKAGE_TYPE = :cargo
      PACKAGE_TYPE_NAME = "Cargo Package"
      BANNER_NAME = "Cargo packages"

      class << self
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
          "rust"
        end

        sig { override.returns(T.nilable(Pathname)) }
        def package_manager_executable
          which("cargo", ORIGINAL_PATHS)
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if (cargo = package_manager_executable) &&
                         (!cargo.to_s.start_with?("/") || cargo.exist?)
            with_env(cargo_env(cargo)) do
              parse_package_list(`#{cargo} install --list`)
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

          cargo = package_manager_executable!

          with_env(cargo_env(cargo)) do
            Bundle.system(cargo.to_s, "install", "--locked", name, verbose:)
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
          Bundle.system(executable.to_s, "uninstall", name, verbose: false)
        end

        sig { override.params(executable: Pathname).returns(T::Hash[String, String]) }
        def package_manager_env(executable)
          cargo_env(executable)
        end

        sig { params(output: String).returns(T::Array[String]) }
        def parse_package_list(output)
          output.lines.filter_map do |line|
            next if line.match?(/^\s/)

            match = line.match(/\A(?<name>[^\s:]+)\s+v[0-9A-Za-z.+-]+/)
            match[:name] if match
          end.uniq
        end
        private :parse_package_list

        sig { params(cargo: Pathname).returns(T::Hash[String, String]) }
        def cargo_env(cargo)
          {
            "CARGO_HOME"         => ENV.fetch("HOMEBREW_CARGO_HOME", nil),
            "CARGO_INSTALL_ROOT" => ENV.fetch("HOMEBREW_CARGO_INSTALL_ROOT", nil),
            "PATH"               => "#{cargo.dirname}:#{ENV.fetch("PATH")}",
            "RUSTUP_HOME"        => ENV.fetch("HOMEBREW_RUSTUP_HOME", nil),
          }.compact
        end
        private :cargo_env
      end
    end
  end
end
