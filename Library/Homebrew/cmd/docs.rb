# typed: strict
# frozen_string_literal: true

require "utils/browser"

require "abstract_command"

module Homebrew
  module Cmd
    class Docs < AbstractCommand
      cmd_args do
        description <<~EOS
          Open Homebrew's online documentation at <#{HOMEBREW_DOCS_WWW}> in a browser.
        EOS
      end

      sig { override.void }
      def run
        Utils::Browser.open HOMEBREW_DOCS_WWW
      end
    end
  end
end
