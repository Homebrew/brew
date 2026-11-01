# typed: strict
# frozen_string_literal: true

require "bundle/extensions/extension"

module Homebrew
  module Bundle
    class Go < Extension
      NON_GO_EXECUTABLE_ERRORS = ["not a Go executable", "unrecognized file format"].freeze
      private_constant :NON_GO_EXECUTABLE_ERRORS

      class << self
        sig { override.returns(Symbol) }
        def type = :go

        sig { override.returns(String) }
        def check_label = "Go Package"

        sig { override.returns(String) }
        def banner_name = "Go packages"

        sig { override.void }
        def reset!
          @packages = T.let(nil, T.nilable(T::Array[String]))
          @installed_packages = T.let(nil, T.nilable(T::Array[String]))
        end

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          banner_name
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if (go = package_manager_executable)
            # Go uses `command-line-arguments` for binaries built from source files rather than a package.
            # These binaries have no package path that Bundle can reinstall.
            # https://github.com/golang/go/issues/36043
            discovered_binaries(go).values.reject { |path| path == "command-line-arguments" }.uniq
          else
            []
          end
        end

        sig { params(go: Pathname).returns(T::Hash[String, String]) }
        def discovered_binaries(go)
          ENV["GOBIN"] = ENV.fetch("HOMEBREW_GOBIN", nil)
          ENV["GOPATH"] = ENV.fetch("HOMEBREW_GOPATH", nil)

          gobin = command_output(go, args: ["env", "GOBIN"], print_stderr: true).chomp
          gopath = command_output(go, args: ["env", "GOPATH"], print_stderr: true).chomp
          bin_dir = gobin.empty? ? "#{gopath}/bin" : gobin

          begin
            entries = Dir.children(bin_dir).sort
          rescue Errno::ENOENT
            return {}
          end

          entries.each_with_object({}) do |entry, binaries|
            next if entry.start_with?(".")

            binary = File.join(bin_dir, entry)
            next unless File.executable?(binary)
            next if File.directory?(binary) || File.symlink?(binary)

            path = binary_package_path(go, binary)
            binaries[binary] = path if path
          end
        end
        private :discovered_binaries

        sig { params(go: Pathname, binary: String).returns(T.nilable(String)) }
        def binary_package_path(go, binary)
          result = SystemCommand.run(go, args: ["version", "-m", binary], print_stderr: false)
          if result.exit_status == 1 && result.stdout.empty?
            NON_GO_EXECUTABLE_ERRORS.each do |diagnostic|
              return nil if result.stderr.chomp ==
                            "#{binary}: could not read Go build info from #{binary}: #{diagnostic}"
            end
          end

          result.assert_success!

          path_line = result.stdout.each_line.find { |line| line.start_with?("\tpath\t") }
          return unless path_line

          path = path_line.delete_prefix("\tpath\t").chomp
          if path.empty? || path.match?(/\s/)
            raise "Invalid Go package path for #{binary.inspect}: #{path.inspect}"
          end

          path
        end
        private :binary_package_path

        sig {
          override.params(
            name:    String,
            with:    T.nilable(T::Array[String]),
            verbose: T::Boolean,
          ).returns(T::Boolean)
        }
        def install_package!(name, with: nil, verbose: false)
          _ = with

          go = package_manager_executable!

          Bundle.system(go.to_s, "install", "#{name}@latest", verbose:)
        end

        sig { override.returns(T::Array[String]) }
        def installed_packages
          @installed_packages ||= packages.dup
        end

        sig { override.params(items: T::Array[String]).void }
        def cleanup!(items)
          go = package_manager_executable
          if go.nil?
            ofail "Failed to remove Go executables: go executable not found" unless items.empty?
            return
          end

          removed = 0
          # Finish discovery before deleting anything so an inspection failure cannot leave partial cleanup.
          discovered_binaries(go).each do |binary, package_path|
            next unless items.include?(package_path)

            begin
              File.unlink(binary)
            rescue Errno::ENOENT
              next
            rescue SystemCallError => e
              ofail "Failed to remove Go executable #{binary}: #{e}"
              next
            end
            removed += 1
          end
          puts "Removed #{Utils.pluralize("Go executable", removed, include_count: true)}"
        end
      end
    end
  end
end
