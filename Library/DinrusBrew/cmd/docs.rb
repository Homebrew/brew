# typed: strict
# frozen_string_literal: true

require "abstract_command"

module DinrusBrew
  module Cmd
    class Docs < AbstractCommand
      cmd_args do
        description <<~EOS
          Open DinrusBrew's online documentation at <#{DINRUSBREW_DOCS_WWW}> in a browser.
        EOS
      end

      sig { override.void }
      def run
        exec_browser DINRUSBREW_DOCS_WWW
      end
    end
  end
end
