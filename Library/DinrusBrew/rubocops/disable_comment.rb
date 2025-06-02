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
          next unless disable_comment?(comment)
          next if comment?(processed_source[comment.loc.line - 2])

          add_offense(comment)
        end
      end

      private

      sig { params(comment: Parser::Source::Comment).returns(T::Boolean) }
      def disable_comment?(comment)
        comment.text.start_with? "# rubocop:disable"
      end

      sig { params(line: String).returns(T::Boolean) }
      def comment?(line)
        line.strip.start_with?("#") && line.strip.delete_prefix("#") != ""
      end
    end
  end
end
