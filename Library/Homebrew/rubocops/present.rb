# typed: true
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Checks for code that can be written with simpler conditionals
      # using `Object#present?`.
      #
      # @example
      #   # Converts usages of `!nil? && !empty?` to `present?`
      #
      #   # bad
      #   !foo.nil? && !foo.empty?
      #
      #   # bad
      #   foo != nil && !foo.empty?
      #
      #   # good
      #   foo.present?
      class Present < Base
        extend AutoCorrector

        MSG_EXISTS_AND_NOT_EMPTY = "Use `%<prefer>s` instead of `%<current>s`."

        def_node_matcher :exists_and_not_empty?, <<~PATTERN
          (and
              {
                (send (send $_ :nil?) :!)
                (send (send $_ :!) :!)
                (send $_ :!= nil)
                $_
              }
              {
                (send (send $_ :empty?) :!)
              }
          )
        PATTERN

        def on_and(node)
          exists_and_not_empty?(node) do |var1, var2|
            return if var1 != var2

            message = format(MSG_EXISTS_AND_NOT_EMPTY, prefer: replacement(var1), current: node.source)

            add_offense(node, message:) do |corrector|
              autocorrect(corrector, node)
            end
          end
        end

        def on_or(node)
          exists_and_not_empty?(node) do |var1, var2|
            return if var1 != var2

            add_offense(node, message: MSG_EXISTS_AND_NOT_EMPTY) do |corrector|
              autocorrect(corrector, node)
            end
          end
        end

        def autocorrect(corrector, node)
          variable1, _variable2 = exists_and_not_empty?(node)
          range = node.source_range
          corrector.replace(range, replacement(variable1))
        end

        private

        def replacement(node)
          node.respond_to?(:source) ? "#{node.source}.present?" : "present?"
        end
      end
    end
  end
end
