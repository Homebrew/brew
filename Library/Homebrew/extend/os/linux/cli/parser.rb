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
          args["formula?"] = true if args.respond_to?(:formula?)
        end
      end
    end
  end
end

Homebrew::CLI::Parser.prepend(OS::Linux::CLI::Parser)
