# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module CLI
      module Parser
        extend T::Helpers

        requires_ancestor { Homebrew::CLI::Parser }

        sig { void }
        def set_default_options
          args.set_arg(:formula?, true)
        end

        sig { void }
        def validate_options
          return unless args.respond_to?(:cask?)
          return unless T.unsafe(self).args.cask?

          # NOTE: We don't raise an error here because we don't want
          #       to print the help page or a stack trace.
          odie "Invalid `--cask` usage: Casks do not work on Linux"
        end
      end
    end
  end
end

Homebrew::CLI::Parser.prepend(OS::Linux::CLI::Parser)
