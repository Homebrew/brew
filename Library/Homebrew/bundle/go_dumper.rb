# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module GoDumper
      sig { void }
      def self.reset!
        @packages = nil
      end

      sig { returns(T::Array[String]) }
      def self.packages
        @packages ||= T.let(nil, T.nilable(T::Array[String]))
        @packages ||= if Bundle.go_installed?
          go = Bundle.which_go
          ENV["GOBIN"] = ENV.fetch("HOMEBREW_GOBIN", nil)
          ENV["GOPATH"] = ENV.fetch("HOMEBREW_GOPATH", nil)
          gobin = `#{go} env GOBIN`.chomp
          gopath = `#{go} env GOPATH`.chomp
          bin_dir = gobin.empty? ? "#{gopath}/bin" : gobin

          return [] unless File.directory?(bin_dir)

          binaries = Dir.glob("#{bin_dir}/*").select do |f|
            File.executable?(f) && !File.directory?(f) && !File.symlink?(f)
          end

          binaries.filter_map do |binary|
            output = `#{go} version -m "#{binary}" 2>/dev/null`
            next if output.empty?

            # Parse the output to find the path line
            # Format: "\tpath\tgithub.com/user/repo"
            lines = output.split("\n")
            path_line = lines.find { |line| line.strip.start_with?("path\t") }
            next unless path_line

            # Extract the package path (second field after splitting by tab)
            # The line format is: "\tpath\tgithub.com/user/repo"
            parts = path_line.split("\t")
            path = parts[2]&.strip if parts.length >= 3

            # `command-line-arguments` is a dummy package name for binaries built
            # from a list of source files instead of a specific package name.
            # https://github.com/golang/go/issues/36043
            next if path == "command-line-arguments"

            path
          end.compact.uniq
        else
          []
        end
      end

      sig { returns(String) }
      def self.dump
        packages.map { |name| "go \"#{name}\"" }.join("\n")
      end
    end
  end
end
