# frozen_string_literal: true

module Gem::Resolver::Molinillo
  # @!visibility private
  module Delegates
    # Delegates all {Gem::Resolver::Molinillo::ResolutionState} methods to a `#state` property.
    module ResolutionState
      # (see Gem::Resolver::Molinillo::ResolutionState#name)
      def name
        current_state = state || Gem::Resolver::Molinillo::ResolutionState.empty
        current_state.name
      end

      # (see Gem::Resolver::Molinillo::ResolutionState#requirements)
      def requirements
        current_state = state || Gem::Resolver::Molinillo::ResolutionState.empty
        current_state.requirements
      end

      # (see Gem::Resolver::Molinillo::ResolutionState#activated)
      def activated
        current_state = state || Gem::Resolver::Molinillo::ResolutionState.empty
        current_state.activated
      end

      # (see Gem::Resolver::Molinillo::ResolutionState#requirement)
      def requirement
        current_state = state || Gem::Resolver::Molinillo::ResolutionState.empty
        current_state.requirement
      end

      # (see Gem::Resolver::Molinillo::ResolutionState#possibilities)
      def possibilities
        current_state = state || Gem::Resolver::Molinillo::ResolutionState.empty
        current_state.possibilities
      end

      # (see Gem::Resolver::Molinillo::ResolutionState#depth)
      def depth
        current_state = state || Gem::Resolver::Molinillo::ResolutionState.empty
        current_state.depth
      end

      # (see Gem::Resolver::Molinillo::ResolutionState#conflicts)
      def conflicts
        current_state = state || Gem::Resolver::Molinillo::ResolutionState.empty
        current_state.conflicts
      end

      # (see Gem::Resolver::Molinillo::ResolutionState#unused_unwind_options)
      def unused_unwind_options
        current_state = state || Gem::Resolver::Molinillo::ResolutionState.empty
        current_state.unused_unwind_options
      end
    end
  end
end
