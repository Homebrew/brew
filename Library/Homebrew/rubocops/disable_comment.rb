# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    # Checks if rubocop disable comments have a clarifying comment preceding them.
    class DisableComment < Base
      MSG = "Add a clarifying comment to the RuboCop disable comment"

      sig { void }
      def on_new_investigation
        super

        processed_source.comments.each do |comment|
          next unless comment.text.start_with? "# rubocop:disable"

          previous_line = processed_source[comment.loc.line - 2]
          next if previous_line.strip.start_with?("#") && previous_line.strip.delete_prefix("#") != ""

          add_offense(comment)
        end
      end
    end
  end
end
