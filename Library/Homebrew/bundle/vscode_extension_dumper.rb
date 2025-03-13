# typed: true
# frozen_string_literal: true

module Bundle
  module VscodeExtensionDumper
    module_function

    def reset!
      @extensions = nil
    end

    def extensions
      @extensions ||= if Bundle.vscode_installed?
        Bundle.exchange_uid_if_needed! do
          `code --list-extensions 2>/dev/null`
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
