# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module CargoDumper
      sig { void }
      def self.reset!
        @packages = nil
      end

      sig { returns(T::Array[String]) }
      def self.packages
        @packages ||= T.let(nil, T.nilable(T::Array[String]))
        @packages ||= if Bundle.cargo_installed?
          require "bundle/cargo_installer"
          cargo = Bundle.which_cargo
          parse_package_list(`#{cargo} install --list`)
        else
          []
        end
      end

      sig { returns(String) }
      def self.dump
        packages.map { |name| "cargo \"#{name}\"" }.join("\n")
      end

      sig { params(output: String).returns(T::Array[String]) }
      private_class_method def self.parse_package_list(output)
        output.lines.filter_map do |line|
          next if line.match?(/^\s/)

          match = line.match(/\A(?<name>[^\s:]+)\s+v[0-9A-Za-z.+-]+/)
          match[:name] if match
        end.uniq
      end
    end
  end
end
