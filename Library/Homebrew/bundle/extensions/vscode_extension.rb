# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class VscodeExtension < Extension
      PACKAGE_TYPE = :vscode
      PACKAGE_TYPE_NAME = "VSCode Extension"
      BANNER_NAME = "VSCode (and forks/variants) extensions"

      class << self
        sig { override.void }
        def reset!
          @extensions = T.let(nil, T.nilable(T::Array[String]))
          @installed_extensions = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          "VSCode extensions"
        end

        sig { override.params(name: String, with: T.nilable(T::Array[String])).returns(Object) }
        def package_record(name, with: nil)
          _ = with

          name.downcase
        end

        sig { override.returns(T.nilable(Pathname)) }
        def package_manager_executable
          which("code", ORIGINAL_PATHS) ||
            which("codium", ORIGINAL_PATHS) ||
            which("cursor", ORIGINAL_PATHS) ||
            which("code-insiders", ORIGINAL_PATHS)
        end

        sig { returns(T::Array[String]) }
        def extensions
          extensions = @extensions
          return extensions if extensions

          @extensions = if (vscode = package_manager_executable)
            Bundle.exchange_uid_if_needed! do
              ENV["WSL_DISTRO_NAME"] = ENV.fetch("HOMEBREW_WSL_DISTRO_NAME", nil)
              `"#{vscode}" --list-extensions 2>/dev/null`
            end.split("\n").map(&:downcase)
          end
          return [] if @extensions.nil?

          @extensions
        end

        sig { override.returns(T::Array[String]) }
        def packages
          extensions
        end

        sig { override.returns(T::Array[String]) }
        def installed_packages
          installed_extensions
        end

        sig { returns(T::Array[String]) }
        def installed_extensions
          installed_extensions = @installed_extensions
          return installed_extensions if installed_extensions

          @installed_extensions = extensions.dup
        end

        sig { override.params(name: String, with: T.nilable(T::Array[String])).returns(T::Boolean) }
        def package_installed?(name, with: nil)
          _ = with

          installed_extensions.include?(name.downcase)
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
          _ = with
          _ = no_upgrade

          if !package_manager_installed? && Bundle.cask_installed?
            puts "Installing visual-studio-code. It is not currently installed." if verbose
            Bundle.system(HOMEBREW_BREW_FILE, "install", "--cask", "visual-studio-code", verbose:)
          end

          if package_installed?(name)
            puts "Skipping install of #{name} VSCode extension. It is already installed." if verbose
            return false
          end

          unless package_manager_installed?
            raise "Unable to install #{name} VSCode extension. VSCode is not installed."
          end

          true
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

          vscode = package_manager_executable!

          Bundle.exchange_uid_if_needed! do
            Bundle.system(vscode, "--install-extension", name, verbose:)
          end
        end

        sig {
          override.params(
            name:       String,
            with:       T.nilable(T::Array[String]),
            preinstall: T::Boolean,
            no_upgrade: T::Boolean,
            verbose:    T::Boolean,
            force:      T::Boolean,
            _options:   Homebrew::Bundle::EntryOption,
          ).returns(T::Boolean)
        }
        def install!(name, with: nil, preinstall: true, no_upgrade: false, verbose: false, force: false,
                     **_options)
          _ = with
          _ = no_upgrade
          _ = force

          return true unless preinstall

          puts "Installing #{name} VSCode extension. It is not currently installed." if verbose
          return false unless install_package!(name, verbose:)

          package = T.cast(package_record(name), String)
          installed_extensions << package unless installed_extensions.include?(package)
          if @extensions
            @extensions << package unless @extensions.include?(package)
          else
            @extensions = [package]
          end

          true
        end

        sig { params(entries: T::Array[Object]).returns(T::Array[String]) }
        def cleanup_items(entries)
          kept_extensions = entries.filter_map do |entry|
            entry = T.cast(entry, Dsl::Entry)
            entry.name.downcase if entry.type == type
          end

          return [].freeze if kept_extensions.empty?

          packages - kept_extensions
        end

        sig { params(extensions: T::Array[String]).void }
        def cleanup!(extensions)
          vscode = package_manager_executable
          return if vscode.nil?

          Bundle.exchange_uid_if_needed! do
            extensions.each do |extension|
              Kernel.system(vscode.to_s, "--uninstall-extension", extension)
            end
          end
        end
      end
    end
  end
end
