# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module CLI
      module Parser
        extend T::Helpers

        requires_ancestor { DinrusBrew::CLI::Parser }

        sig { void }
        def set_default_options
          return if args.only_formula_or_cask == :cask

          args.set_arg(:formula?, true)
        end
      end
    end
  end
end

DinrusBrew::CLI::Parser.prepend(OS::Linux::CLI::Parser)
