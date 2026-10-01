# typed: strict
# frozen_string_literal: true

require "system_command"
require "utils/output"
require "utils/shell"

module Utils
  module Editor
    module_function

    sig { params(silent: T::Boolean).returns(String) }
    def command(silent: false)
      editor = Homebrew::EnvConfig.editor
      return editor if editor

      editor = %w[code codium cursor code-insiders subl mate bbedit vim].find do |candidate|
        candidate if Utils::Shell.which(candidate, ORIGINAL_PATHS)
      end
      editor ||= "vim"

      unless silent
        Utils::Output.opoo <<~EOS
          Using #{editor} because no editor was set in the environment.
          This may change in the future, so we recommend setting `$EDITOR`
          or `$HOMEBREW_EDITOR` to your preferred text editor.
        EOS
      end

      editor
    end

    sig { params(filenames: T.any(String, Pathname)).void }
    def open(*filenames)
      $stdout.puts "Editing #{filenames.join "\n"}"
      Utils::Shell.with_homebrew_path { SystemCommand.safe_system(*command.shellsplit, *filenames) }
    end
  end
end
