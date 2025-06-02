# frozen_string_literal: true

module Bundler::Molinillo
  # @!visibility private
  module Delegates
    # Delegates all {Bundler::Molinillo::ResolutionState} methods to a `#state` property.
    module ResolutionState
      # (see Bundler::Molinillo::ResolutionState#name)
      def name
        current_state = state || Bundler::Molinillo::ResolutionState.empty
        current_state.name
      end

      # (see Bundler::Molinillo::ResolutionState#requirements)
      def requirements
        current_state = state || Bundler::Molinillo::ResolutionState.empty
        current_state.requirements
      end

      # (see Bundler::Molinillo::ResolutionState#activated)
      def activated
        current_state = state || Bundler::Molinillo::ResolutionState.empty
        current_state.activated
      end

      # (see Bundler::Molinillo::ResolutionState#requirement)
      def requirement
        current_state = state || Bundler::Molinillo::ResolutionState.empty
        current_state.requirement
      end

      # (see Bundler::Molinillo::ResolutionState#possibilities)
      def possibilities
        current_state = state || Bundler::Molinillo::ResolutionState.empty
        current_state.possibilities
      end

      # (see Bundler::Molinillo::ResolutionState#depth)
      def depth
        current_state = state || Bundler::Molinillo::ResolutionState.empty
        current_state.depth
      end

      # (see Bundler::Molinillo::ResolutionState#conflicts)
      def conflicts
        current_state = state || Bundler::Molinillo::ResolutionState.empty
        current_state.conflicts
      end

      # (see Bundler::Molinillo::ResolutionState#unused_unwind_options)
      def unused_unwind_options
        current_state = state || Bundler::Molinillo::ResolutionState.empty
        current_state.unused_unwind_options
      end
    end
  end
end
