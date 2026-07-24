# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Flags `send`-family dispatch in tests. Tests should exercise methods the way real
      # callers do: a private method poked via `send` should be made public and called
      # directly instead.
      #
      # - `send`/`__send__` are always flagged: with a static method name the call can be
      #   written directly (after making the method public if needed); with a dynamic one
      #   it must go through `public_send` so it cannot bypass method visibility.
      # - `public_send` is flagged only when the method name is a literal that could have
      #   been written as a direct call. A dynamic name (`public_send(method_name)`,
      #   `public_send(:"#{artifact_dsl_key}_phase")`) is the one legitimate use:
      #   parameterised dispatch to public API. A literal name with no direct call syntax
      #   (e.g. `:"gcc-9"`) is also allowed, as no direct call can spell it.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # formula.send(:active_spec)
      #
      # # good (with `active_spec` made public)
      # formula.active_spec
      #
      # # good (dynamic dispatch to public API in a parameterised example)
      # subject.public_send(:"#{artifact_dsl_key}_phase")
      # ```
      class NoSendInTests < Base
        MSG_SEND = "Make the method public and call it directly instead of using `%<method>s` in tests."
        MSG_SEND_DYNAMIC = "Use `public_send` instead of `%<method>s` in tests; " \
                           "`%<method>s` bypasses method visibility."
        MSG_PUBLIC_SEND = "Call the method directly instead of using `public_send` with a static method name."
        RESTRICT_ON_SEND = [:send, :__send__, :public_send].freeze

        # A literal method name that direct call syntax can spell, including setters
        # (`public_send(:foo=, value)` can be written `receiver.foo = value`).
        DIRECTLY_CALLABLE_NAME = /\A[a-zA-Z_][a-zA-Z0-9_]*[?!=]?\z/

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          directly_callable = directly_callable_name?(node.first_argument)

          message = if node.method_name == :public_send
            return unless directly_callable

            MSG_PUBLIC_SEND
          elsif directly_callable
            format(MSG_SEND, method: node.method_name)
          else
            format(MSG_SEND_DYNAMIC, method: node.method_name)
          end

          add_offense(node.loc.selector, message:)
        end
        alias on_csend on_send

        private

        sig { params(argument: T.nilable(RuboCop::AST::Node)).returns(T::Boolean) }
        def directly_callable_name?(argument)
          return false unless argument
          return false if !argument.sym_type? && !argument.str_type?

          argument.children.first.to_s.match?(DIRECTLY_CALLABLE_NAME)
        end
      end
    end
  end
end
