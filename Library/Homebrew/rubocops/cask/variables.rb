# typed: strict
# frozen_string_literal: true

require "forwardable"

module RuboCop
  module Cop
    module Cask
      # This cop audits variables in casks.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # cask do
      #   arch = Hardware::CPU.intel? ? "darwin" : "darwin-arm64"
      # end
      #
      # # good
      # cask 'foo' do
      #   arch arm: "darwin-arm64", intel: "darwin"
      # end
      # ```
      class Variables < Base
        extend Forwardable
        extend AutoCorrector
        include CaskHelp

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          @cask_block = T.let(cask_block, T.nilable(RuboCop::Cask::AST::CaskBlock))
          add_offenses
        end

        private

        def_delegator :@cask_block, :cask_node

        sig { void }
        def add_offenses
          variable_assignment(cask_node) do |node, var_name, arch_condition, true_node, false_node|
            arm_node, intel_node = if arch_condition == :arm?
              [true_node, false_node]
            else
              [false_node, true_node]
            end

            replacement_string = if var_name == :arch
              "arch "
            else
              "#{var_name} = on_arch_conditional "
            end
            replacement_parameters = []
            replacement_parameters << "arm: #{arm_node.source}" unless blank_node?(arm_node)
            replacement_parameters << "intel: #{intel_node.source}" unless blank_node?(intel_node)
            replacement_string += replacement_parameters.join(", ")

            add_offense(node, message: "Use `#{replacement_string}` instead of `#{node.source}`.") do |corrector|
              corrector.replace(node, replacement_string)
            end
          end
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def blank_node?(node)
          case node.type
          when :str
            node.str_content.empty?
          when :nil
            true
          else
            false
          end
        end

        def_node_search :variable_assignment, <<~PATTERN
          $(lvasgn $_ (if (send (const (const nil? :Hardware) :CPU) ${:arm? :intel?}) $_ $_))
        PATTERN
      end
    end
  end
end
