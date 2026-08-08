# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Prevents structured install-step runners from depending on formula
      # source, formula resources or direct downloads after a bottle is poured.
      class InstallStepsSourceIndependence < Base
        MSG = "Install-step runners must use bottled files and API context " \
              "without loading formula source or resources."
        SOURCE_CONSTANTS = %w[Formula Formulary Resource].freeze

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          add_offense(node) if source_dependent?(node)
        end
        alias on_csend on_send

        sig { params(node: RuboCop::AST::ConstNode).void }
        def on_const(node)
          return unless SOURCE_CONSTANTS.include?(node.const_name)

          parent = node.parent
          return if parent.is_a?(RuboCop::AST::SendNode) && parent.receiver == node

          add_offense(node)
        end

        private

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def source_dependent?(node)
          return true if node.method?(:resource)

          receiver = node.receiver
          return false unless receiver.is_a?(RuboCop::AST::ConstNode)
          return true if SOURCE_CONSTANTS.include?(receiver.const_name)
          return true if receiver.const_name == "Utils::Curl"

          receiver.const_name == "URI" && (node.method?(:open) || node.method?(:read))
        end
      end
    end
  end
end
