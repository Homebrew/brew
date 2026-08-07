# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Enforces the use of `String#unpack1` and `Array#pack` over the
      # `base64` gem, which Homebrew no longer includes.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # require "base64"
      # Base64.decode64(encoded)
      # Base64.strict_encode64(decoded)
      #
      # # good
      # encoded.unpack1("m")
      # [decoded].pack("m0")
      # ```
      class NoBase64 < Base
        include RangeHelp
        extend AutoCorrector

        MSG = "Homebrew no longer includes the `base64` gem; " \
              "use `String#unpack1` or `Array#pack` instead."

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          if require_base64?(node)
            add_offense(node) do |corrector|
              parent = node.parent
              next if parent && !parent.begin_type?

              corrector.remove(range_by_whole_lines(node.source_range, include_final_newline: true))
            end
          elsif top_level_const?(node.receiver, :Base64)
            add_offense(node) do |corrector|
              autocorrect_base64_call(corrector, node)
            end
          end
        end
        alias on_csend on_send

        sig { params(node: RuboCop::AST::ConstNode).void }
        def on_const(node)
          return unless top_level_const?(node, :Base64)

          parent = node.parent
          return if parent.is_a?(RuboCop::AST::SendNode) && parent.receiver == node
          # Formulae for base64 tools are legitimately named `Base64`.
          return if parent.is_a?(RuboCop::AST::ClassNode) && parent.identifier == node

          add_offense(node)
        end

        private

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def require_base64?(node)
          return false unless node.method?(:require)

          receiver = node.receiver
          return false if receiver && !top_level_const?(receiver, :Kernel)

          arg = node.first_argument
          node.arguments.one? && arg.is_a?(RuboCop::AST::StrNode) && arg.value == "base64"
        end

        sig { params(node: T.nilable(RuboCop::AST::Node), name: Symbol).returns(T::Boolean) }
        def top_level_const?(node, name)
          return false unless node.is_a?(RuboCop::AST::ConstNode)
          return false if node.short_name != name

          namespace = node.namespace
          namespace.nil? || namespace.cbase_type?
        end

        sig { params(corrector: RuboCop::Cop::Corrector, node: RuboCop::AST::SendNode).void }
        def autocorrect_base64_call(corrector, node)
          return unless node.arguments.one?

          arg = node.first_argument
          replacement = case node.method_name
          when :decode64, :strict_decode64
            directive = (node.method_name == :decode64) ? "m" : "m0"
            "#{arg.source}.unpack1(\"#{directive}\")" if chainable?(arg)
          when :encode64, :strict_encode64
            directive = (node.method_name == :encode64) ? "m" : "m0"
            "[#{arg.source}].pack(\"#{directive}\")" if !arg.splat_type? && !arg.block_pass_type?
          end
          return if replacement.nil?

          corrector.replace(node, replacement)
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def chainable?(node)
          if node.is_a?(RuboCop::AST::SendNode)
            !node.operator_method? && !node.assignment_method?
          else
            node.variable? || node.const_type? || node.begin_type? ||
              (node.literal? && !node.range_type?)
          end
        end
      end
    end
  end
end
