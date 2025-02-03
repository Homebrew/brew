# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Checks for code that can be simplified using `Object#blank?`.
      #
      # NOTE: Auto-correction for this cop is unsafe because `' '.empty?` returns `false`,
      #       but `' '.blank?` returns `true`. Therefore, auto-correction is not compatible
      #       if the receiver is a non-empty blank string.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # foo.nil? || foo.empty?
      # foo == nil || foo.empty?
      #
      # # good
      # foo.blank?
      # ```
      class Blank < Base
        extend AutoCorrector

        MSG = "Use `%<prefer>s` instead of `%<current>s`."

        # `(send nil $_)` is not actually a valid match for an offense. Nodes
        # that have a single method call on the left hand side
        # (`bar || foo.empty?`) will blow up when checking
        # `(send (:nil) :== $_)`.
        def_node_matcher :nil_or_empty?, <<~PATTERN
          (or
              {
                (send $_ :!)
                (send $_ :nil?)
                (send $_ :== nil)
                (send nil :== $_)
              }
              {
                (send $_ :empty?)
                (send (send (send $_ :empty?) :!) :!)
              }
          )
        PATTERN

        sig { params(node: RuboCop::AST::Node).void }
        def on_or(node)
          nil_or_empty?(node) do |var1, var2|
            return if var1 != var2

            message = format(MSG, prefer: replacement(var1), current: node.source)
            add_offense(node, message:) do |corrector|
              autocorrect(corrector, node)
            end
          end
        end

        private

        sig { params(corrector: RuboCop::Cop::Corrector, node: RuboCop::AST::Node).void }
        def autocorrect(corrector, node)
          variable1, _variable2 = nil_or_empty?(node)
          range = node.source_range
          corrector.replace(range, replacement(variable1))
        end

        sig { params(node: T.nilable(RuboCop::AST::Node)).returns(String) }
        def replacement(node)
          node.respond_to?(:source) ? "#{node&.source}.blank?" : "blank?"
        end
      end
    end
  end
end
