# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "abstract_command"
require "services/formula_wrapper"

module Homebrew
  module Cmd
    class Services < Homebrew::AbstractCommand
      # `include`d by every `Services` subcommand that reads `targets`, to narrow it from
      # `AbstractSubcommand`'s generic `T.anything`, since these are always dispatched with one.
      module SubcommandTargetsReader
        extend T::Helpers

        requires_ancestor { Homebrew::AbstractSubcommand }

        sig { returns(T::Array[Homebrew::Services::FormulaWrapper]) }
        def targets
          targets = super
          unless targets.is_a?(Array)
            raise TypeError, "#{self.class} has no `targets`, but is not constructed through `Services.dispatch`"
          end

          targets
        end
      end
    end
  end
end
