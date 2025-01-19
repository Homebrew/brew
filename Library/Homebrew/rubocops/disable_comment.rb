# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    # Checks if rubocop disable comments have a clarifying comment preceding them.
    class DisableComment < Base
      MSG = "Add a clarifying comment to the RuboCop disable comment"

      def on_new_investigation
        super

        processed_source.comments.each do |comment|
          next unless disable_comment?(comment)
          next if comment?(processed_source[comment.loc.line - 2])

          add_offense(comment)
        end
      end

      private

      def disable_comment?(comment)
        comment.text.start_with? "# rubocop:disable"
      end

      def comment?(line)
        line.strip.start_with? "#"
      end
    end
  end
end
