# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop disallows bare operating-system dependencies inside OS blocks.
      # It also disallows Linux dependencies inside architecture-only blocks,
      # where the DSL ignores their platform restriction. macOS dependencies
      # remain allowed there because they change the cask's supported platforms.
      # There is no autocorrection because choosing between moving and removing
      # the dependency requires knowing the cask's intended platform support.
      class NoNestedOSDependency < Base
        OS_DEPENDENCIES = [:macos, :linux].freeze
        ARCH_BLOCK_METHODS = [:on_arm, :on_intel].freeze
        OS_BLOCK_METHODS = T.let(
          [
            *RuboCop::Cask::Constants::ON_SYSTEM_METHODS.reject { |method| ARCH_BLOCK_METHODS.include?(method) },
            :on_system,
          ].freeze,
          T::Array[Symbol],
        )
        OS_DISPLAY_NAMES = T.let({ macos: "macOS", linux: "Linux" }.freeze, T::Hash[Symbol, String])
        MSG = "A bare %<os_name>s dependency must not be nested in this conditional block. " \
              "Move it to the top level if the cask is %<os_name>s-only; otherwise remove it."

        RESTRICT_ON_SEND = [:depends_on].freeze

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return if node.receiver
          return unless (os = os_dependency(node))
          return unless inside_disallowed_block_in_cask?(node, os)

          add_offense(node, message: format(MSG, os_name: OS_DISPLAY_NAMES.fetch(os)))
        end

        private

        sig { params(node: RuboCop::AST::SendNode).returns(T.nilable(Symbol)) }
        def os_dependency(node)
          argument = node.first_argument
          return OS_DEPENDENCIES.find { |os| os == argument.value } if argument&.sym_type?

          node.arguments.each do |node_argument|
            next unless node_argument.hash_type?

            node_argument.pairs.each do |pair|
              key = pair.key
              value = pair.value
              next unless key.sym_type?
              next unless value.sym_type?
              next if value.value != :any

              os = OS_DEPENDENCIES.find { |dependency| dependency == key.value }
              return os if os
            end
          end

          nil
        end

        sig { params(node: RuboCop::AST::SendNode, os: Symbol).returns(T::Boolean) }
        def inside_disallowed_block_in_cask?(node, os)
          block_methods = if os == :linux
            [*RuboCop::Cask::Constants::ON_SYSTEM_METHODS, :on_system]
          else
            OS_BLOCK_METHODS
          end
          nested_in_disallowed_block = T.let(false, T::Boolean)
          node.each_ancestor(:block) do |ancestor|
            next unless ancestor.is_a?(RuboCop::AST::BlockNode)

            return nested_in_disallowed_block if ancestor.cask_block?

            send_node = ancestor.send_node
            next if send_node.receiver

            nested_in_disallowed_block = true if block_methods.include?(send_node.method_name)
          end

          false
        end
      end
    end
  end
end
