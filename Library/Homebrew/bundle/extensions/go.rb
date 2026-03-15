# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class Go < Extension
      PACKAGE_TYPE = :go
      PACKAGE_TYPE_NAME = "Go Package"
      BANNER_NAME = "Go packages"

      class << self
        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[String]))
          @installed_packages = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if Bundle.go_installed?
            go = Bundle.which_go
            return [] if go.nil?

            ENV["GOBIN"] = ENV.fetch("HOMEBREW_GOBIN", nil)
            ENV["GOPATH"] = ENV.fetch("HOMEBREW_GOPATH", nil)
            gobin = `#{go} env GOBIN`.chomp
            gopath = `#{go} env GOPATH`.chomp
            bin_dir = gobin.empty? ? "#{gopath}/bin" : gobin

            return [] unless File.directory?(bin_dir)

            binaries = Dir.glob("#{bin_dir}/*").select do |file|
              File.executable?(file) && !File.directory?(file) && !File.symlink?(file)
            end

            binaries.filter_map do |binary|
              output = `#{go} version -m "#{binary}" 2>/dev/null`
              next if output.empty?

              lines = output.split("\n")
              path_line = lines.find { |line| line.strip.start_with?("path\t") }
              next unless path_line

              # Parse the output to find the path line
              # Format: "\tpath\tgithub.com/user/repo"
              parts = path_line.split("\t")
              # Extract the package path (second field after splitting by tab)
              # The line format is: "\tpath\tgithub.com/user/repo"
              path = parts[2]&.strip

              # `command-line-arguments` is a dummy package name for binaries built
              # from a list of source files instead of a specific package name.
              # https://github.com/golang/go/issues/36043
              next if path == "command-line-arguments"

              path
            end.uniq
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

          go = package_manager_executable
          return false if go.nil?

          Bundle.system(go.to_s, "install", "#{name}@latest", verbose:)
        end

        sig { override.returns(T::Array[String]) }
        def installed_packages
          installed_packages = @installed_packages
          return installed_packages if installed_packages

          @installed_packages = packages.dup
        end
      end
    end

    # TODO: Remove these compatibility aliases once bundle callers and tests
    # stop requiring separate go dumper/installer/checker constants.
    GoDumper = Go
    GoInstaller = Go

    module Checker
      # TODO: Remove this compatibility alias once bundle callers and tests stop
      # requiring a separate go checker constant.
      GoChecker = Homebrew::Bundle::Go
    end
  end
end
