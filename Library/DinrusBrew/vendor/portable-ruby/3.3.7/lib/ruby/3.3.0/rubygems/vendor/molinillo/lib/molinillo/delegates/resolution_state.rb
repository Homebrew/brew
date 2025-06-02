# frozen_string_literal: true

module Gem::Molinillo
  # @!visibility private
  module Delegates
    # Delegates all {Gem::Molinillo::ResolutionState} methods to a `#state` property.
    module ResolutionState
      # (see Gem::Molinillo::ResolutionState#name)
      def name
        current_state = state || Gem::Molinillo::ResolutionState.empty
        current_state.name
      end

      # (see Gem::Molinillo::ResolutionState#requirements)
      def requirements
        current_state = state || Gem::Molinillo::ResolutionState.empty
        current_state.requirements
      end

      # (see Gem::Molinillo::ResolutionState#activated)
      def activated
        current_state = state || Gem::Molinillo::ResolutionState.empty
        current_state.activated
      end

      # (see Gem::Molinillo::ResolutionState#requirement)
      def requirement
        current_state = state || Gem::Molinillo::ResolutionState.empty
        current_state.requirement
      end

      # (see Gem::Molinillo::ResolutionState#possibilities)
      def possibilities
        current_state = state || Gem::Molinillo::ResolutionState.empty
        current_state.possibilities
      end

      # (see Gem::Molinillo::ResolutionState#depth)
      def depth
        current_state = state || Gem::Molinillo::ResolutionState.empty
        current_state.depth
      end

      # (see Gem::Molinillo::ResolutionState#conflicts)
      def conflicts
        current_state = state || Gem::Molinillo::ResolutionState.empty
        current_state.conflicts
      end

      # (see Gem::Molinillo::ResolutionState#unused_unwind_options)
      def unused_unwind_options
        current_state = state || Gem::Molinillo::ResolutionState.empty
        current_state.unused_unwind_options
      end
    end
  end
end
