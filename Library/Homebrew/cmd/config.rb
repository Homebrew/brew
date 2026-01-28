# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "system_config"

module Homebrew
  module Cmd
    class Config < AbstractCommand
      cmd_args do
        description <<~EOS
          Show Homebrew and system configuration info useful for debugging. If you file
          a bug report, you will be required to provide this information.
        EOS

        named_args :none
      end

      sig { override.void }
      def run
        SystemConfig.dump_verbose_config
      end
    end
  end
end
