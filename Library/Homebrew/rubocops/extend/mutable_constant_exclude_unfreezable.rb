# typed: strict
# frozen_string_literal: true

require "rubocop/cop/style/mutable_constant"

module RuboCop
  module Cop
    module Sorbet
      # TODO: delete this file when https://github.com/Shopify/rubocop-sorbet/pull/256 is available
      module MutableConstantExcludeUnfreezable
        class << self
          sig { params(base: RuboCop::AST::NodePattern::Macros).void }
          def prepended(base)
            base.def_node_matcher(:t_let, <<~PATTERN)
              (send (const nil? :T) :let $_constant _type)
            PATTERN

            base.def_node_matcher(:t_type_alias?, <<~PATTERN)
              (block (send (const {nil? cbase} :T) :type_alias ...) ...)
            PATTERN

            base.def_node_matcher(:type_member?, <<~PATTERN)
              (block (send nil? :type_member ...) ...)
            PATTERN
          end
        end

        sig { params(value: RuboCop::AST::Node).void }
        def on_assignment(value)
          T.unsafe(self).t_let(value) do |constant|
            value = T.let(constant, RuboCop::AST::Node)
          end
          return if T.unsafe(self).t_type_alias?(value)
          return if T.unsafe(self).type_member?(value)

          super
        end
      end
    end
  end
end

RuboCop::Cop::Style::MutableConstant.prepend(
  RuboCop::Cop::Sorbet::MutableConstantExcludeUnfreezable,
)
