# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Ensures that methods/attributes annotated with `@api public` have
      # proper YARD documentation beyond just the annotation itself.
      # A bare `# @api public` with no preceding description is not sufficient
      # for public API methods.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # # @api public
      # sig { returns(String) }
      # def foo; end
      #
      # # good
      # # The name of this object.
      # #
      # # @api public
      # sig { returns(String) }
      # def foo; end
      # ```
      class PublicApiDocumentation < Base
        MSG = "`@api public` methods must have a descriptive YARD comment, not just the annotation."

        sig { void }
        def on_new_investigation
          super

          processed_source.comments.each do |comment|
            next unless api_public_comment?(comment)

            add_offense(comment) unless descriptive_comment_preceding?(comment)
          end
        end

        private

        sig { params(comment: Parser::Source::Comment).returns(T::Boolean) }
        def api_public_comment?(comment)
          ["# @api public", "@api public"].include?(comment.text.strip)
        end

        sig { params(comment: Parser::Source::Comment).returns(T::Boolean) }
        def descriptive_comment_preceding?(comment)
          lines = processed_source.lines
          line_idx = comment.loc.line - 2 # 0-indexed, line before the @api public comment

          while line_idx >= 0
            line = lines[line_idx]&.strip
            break if line.nil? || !line.start_with?("#")

            content = line.delete_prefix("#").strip
            # Skip blank comment lines and YARD tags
            if content.empty? || content.start_with?("@")
              line_idx -= 1
              next
            end

            return true
          end

          false
        end
      end
    end
  end
end
