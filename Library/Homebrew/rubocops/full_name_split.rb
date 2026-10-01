# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Checks for formula or cask full-name parsing that should use `Utils.name_from_full_name`.
      #
      # ### Examples
      #
      # ```ruby
      # # bad
      # name.split("/").last
      # token.split("/").fetch(-1)
      #
      # # good
      # Utils.name_from_full_name(name)
      # Utils.name_from_full_name(token)
      # ```
      class FullNameSplit < Base
        extend AutoCorrector

        MSG = "Use `Utils.name_from_full_name` instead of splitting formula or cask full names."

        RESTRICT_ON_SEND = [:last, :fetch].freeze
        FULL_NAME_RECEIVER_NAMES = %w[
          cask_full_name
          cask_token
          dep_full_name
          dep_name
          formula_full_name
          formula_name
          full_name
          name
          new_full_name
          new_name
          old_full_name
          old_name
          resolved_full_name
          service_name
          token
        ].freeze
        private_constant :FULL_NAME_RECEIVER_NAMES

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          check_full_name_split(node)
        end

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_csend(node)
          check_full_name_split(node)
        end

        private

        sig { params(node: RuboCop::AST::SendNode).void }
        def check_full_name_split(node)
          return unless basename_call?(node)

          split_call = node.receiver
          return unless split_call.is_a?(RuboCop::AST::SendNode)
          return unless split_call?(node, split_call)

          receiver = split_call.receiver
          return unless receiver
          return unless full_name_receiver?(receiver)

          add_offense(node) do |corrector|
            corrector.replace(node.source_range, replacement(node, receiver))
          end
        end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def basename_call?(node)
          return true if node.method?(:last) && node.arguments.empty?
          return false unless node.method?(:fetch)
          return false if node.arguments.length != 1

          argument = node.first_argument
          argument.is_a?(RuboCop::AST::Node) &&
            argument.int_type? &&
            T.cast(argument, RuboCop::AST::IntNode).value == -1
        end

        sig { params(node: RuboCop::AST::SendNode, split_call: RuboCop::AST::SendNode).returns(T::Boolean) }
        def split_call?(node, split_call)
          return false unless split_call.method?(:split)
          return false if split_call.arguments.length != 1
          return false if split_call.csend_type? != node.csend_type?

          argument = split_call.first_argument
          argument.is_a?(RuboCop::AST::Node) &&
            argument.str_type? &&
            T.cast(argument, RuboCop::AST::StrNode).value == "/"
        end

        sig { params(receiver: RuboCop::AST::Node).returns(T::Boolean) }
        def full_name_receiver?(receiver)
          return false if receiver.source.match?(/(?:\A|[.])tap(?:\.|&\.)full_name\z/)

          identifier = receiver_identifier(receiver)

          !identifier.nil? && FULL_NAME_RECEIVER_NAMES.include?(identifier)
        end

        sig { params(receiver: RuboCop::AST::Node).returns(T.nilable(String)) }
        def receiver_identifier(receiver)
          case receiver.type
          when :lvar, :ivar, :cvar, :gvar
            receiver.source.delete_prefix("@@").delete_prefix("@").delete_prefix("$")
          when :send, :csend
            receiver_method_name(T.cast(receiver, RuboCop::AST::SendNode))
          end
        end

        sig { params(receiver: RuboCop::AST::SendNode).returns(T.nilable(String)) }
        def receiver_method_name(receiver)
          return receiver.method_name.to_s unless receiver.method?(:[])
          return if receiver.arguments.length != 1

          argument = receiver.first_argument
          return unless argument.is_a?(RuboCop::AST::Node)
          return unless argument.str_type?

          T.cast(argument, RuboCop::AST::StrNode).value.to_s
        end

        sig { params(node: RuboCop::AST::SendNode, receiver: RuboCop::AST::Node).returns(String) }
        def replacement(node, receiver)
          if node.csend_type?
            "#{receiver.source}&.then { ::Utils.name_from_full_name(it) }"
          else
            "::Utils.name_from_full_name(#{receiver.source})"
          end
        end
      end
    end
  end
end
