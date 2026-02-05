# typed: strict
# frozen_string_literal: true

module Homebrew
  module Bundle
    module VscodeExtensionDumper
      sig { void }
      def self.reset!
        @extensions = nil
      end

      sig { returns(T::Array[String]) }
      def self.extensions
        @extensions ||= T.let(nil, T.nilable(T::Array[String]))
        @extensions ||= if Bundle.vscode_installed?
          Bundle.exchange_uid_if_needed! do
            ENV["WSL_DISTRO_NAME"] = ENV.fetch("HOMEBREW_WSL_DISTRO_NAME", nil)
            `"#{Bundle.which_vscode}" --list-extensions 2>/dev/null`
          end.split("\n").map(&:downcase)
        else
          []
        end
      end

      sig { returns(String) }
      def self.dump
        extensions.map { |name| "vscode \"#{name}\"" }.join("\n")
      end
    end
  end
end
