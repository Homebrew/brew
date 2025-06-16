# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module VscodeExtensionDumper
      def self.reset!
        @extensions = nil
      end

      def self.extensions
        @extensions ||= if Bundle.vscode_installed?
          Bundle.exchange_uid_if_needed! do
            `"#{Bundle.which_vscode}" --list-extensions 2>/dev/null`
          end.split("\n").map(&:downcase)
        else
          []
        end
      end

      def self.dump
        extensions.map { |name| "vscode \"#{name}\"" }.join("\n")
      end
    end
  end
end
