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

        sig { override.returns(T.nilable(String)) }
        def cleanup_heading
          banner_name
        end

        sig { override.returns(T::Array[String]) }
        def packages
          packages = @packages
          return packages if packages

          @packages = if (go = package_manager_executable)
            ENV["GOBIN"] = ENV.fetch("HOMEBREW_GOBIN", nil)
            ENV["GOPATH"] = ENV.fetch("HOMEBREW_GOPATH", nil)
            gobin = `#{go} env GOBIN`.chomp
            gopath = `#{go} env GOPATH`.chomp
            bin_dir = gobin.empty? ? "#{gopath}/bin" : gobin
            if File.directory?(bin_dir)
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

          go = package_manager_executable!

          Bundle.system(go.to_s, "install", "#{name}@latest", verbose:)
        end

        sig { override.returns(T::Array[String]) }
        def installed_packages
          installed_packages = @installed_packages
          return installed_packages if installed_packages

          @installed_packages = packages.dup
        end

        sig { override.params(items: T::Array[String]).void }
        def cleanup!(items)
          go = package_manager_executable
          return if go.nil?

          gobin = `#{go} env GOBIN`.chomp
          gopath = `#{go} env GOPATH`.chomp
          bin_dir = gobin.empty? ? "#{gopath}/bin" : gobin
          return unless File.directory?(bin_dir)

          removed = 0
          Dir.glob("#{bin_dir}/*").each do |binary|
            next if !File.executable?(binary) || File.directory?(binary) || File.symlink?(binary)

            output = `#{go} version -m "#{binary}" 2>/dev/null`
            next if output.empty?

            path_line = output.split("\n").find { |line| line.strip.start_with?("path\t") }
            next unless path_line

            module_path = path_line.split("\t")[2]&.strip
            next unless items.include?(module_path)

            FileUtils.rm_f(binary)
            removed += 1
          end
          puts "Uninstalled #{removed} #{banner_name}#{"s" if removed != 1}"
        end
      end
    end
  end
end
