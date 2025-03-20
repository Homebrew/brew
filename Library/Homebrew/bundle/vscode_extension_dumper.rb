# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module Bundle
    module VscodeExtensionDumper
      module_function

      def reset!
        @extensions = nil
      end

      def extensions
        @extensions ||= if Bundle.vscode_installed?
          Bundle.exchange_uid_if_needed! do
            `"#{Bundle.which_vscode}" --list-extensions 2>/dev/null`
          end.split("\n").map(&:downcase)
        else
          []
        end
      end

      def dump
        extensions.map { |name| "vscode \"#{name}\"" }.join("\n")
      end
    end
  end
end
