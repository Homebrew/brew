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
            require "json"
            output = `go version -m -json "#{binary}" 2>/dev/null`
            next if output.empty?

            begin
              data = JSON.parse(output)
              data["Path"] if data["Path"]
            rescue JSON::ParserError
              nil
            end
          end.uniq
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
