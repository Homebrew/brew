# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Flags `instance_variable_get`/`instance_variable_set` in tests. Tests should read
      # and write object state through public accessors: add a public `attr_reader`/
      # `attr_writer` (or use an existing accessor) on the class instead of reaching into
      # its instance variables.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # formula.instance_variable_set(:@tap, CoreTap.instance)
      #
      # # good (with a public `attr_writer :tap`)
      # formula.tap = CoreTap.instance
      # ```
      class NoInstanceVariableAccessInTests < Base
        MSG = "Use a public `attr_reader`/`attr_writer` (or an existing accessor) instead of " \
              "`%<method>s` in tests."
        RESTRICT_ON_SEND = [:instance_variable_get, :instance_variable_set].freeze

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          add_offense(node.loc.selector, message: format(MSG, method: node.method_name))
        end
        alias on_csend on_send
      end
    end
  end
end
