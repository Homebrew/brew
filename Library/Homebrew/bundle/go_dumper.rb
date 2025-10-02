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
          gobin = `go env GOBIN`.chomp
          gopath = `go env GOPATH`.chomp
          bin_dir = gobin.empty? ? "#{gopath}/bin" : gobin

          return [] unless File.directory?(bin_dir)

          binaries = Dir.glob("#{bin_dir}/*").select { |f| File.executable?(f) && !File.directory?(f) }

          binaries.filter_map do |binary|
            output = `go version -m "#{binary}" 2>/dev/null`
            next if output.empty?

            # Parse the output to find the path line
            # Format: "\tpath\tgithub.com/user/repo"
            lines = output.split("\n")
            path_line = lines.find { |line| line.strip.start_with?("path\t") }
            next unless path_line

            # Extract the package path (second field after splitting by tab)
            # The line format is: "\tpath\tgithub.com/user/repo"
            parts = path_line.split("\t")
            parts[2]&.strip if parts.length >= 3
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
