# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # This cop checks for the use of `FileUtils.rm_f`, `FileUtils.rm_rf`, or `{FileUtils,instance}.rmtree`
      # and recommends the safer versions.
      class NoFileutilsRmrf < Base
        extend AutoCorrector

        MSG = "Use `rm` or `rm_r` instead of `rm_rf`, `rm_f`, or `rmtree`."

        def_node_matcher :any_receiver_rm_r_f?, <<~PATTERN
          (send
            {(const {nil? cbase} :FileUtils) (self)}
            {:rm_rf :rm_f}
            ...)
        PATTERN

        def_node_matcher :no_receiver_rm_r_f?, <<~PATTERN
          (send nil? {:rm_rf :rm_f} ...)
        PATTERN

        def_node_matcher :no_receiver_rmtree?, <<~PATTERN
          (send nil? :rmtree ...)
        PATTERN

        def_node_matcher :any_receiver_rmtree?, <<~PATTERN
          (send !nil? :rmtree ...)
        PATTERN

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return if neither_rm_rf_nor_rmtree?(node)

          add_offense(node) do |corrector|
            class_name = "FileUtils." if any_receiver_rm_r_f?(node) || any_receiver_rmtree?(node)
            new_method = if node.method?(:rm_rf) || node.method?(:rmtree)
              "rm_r"
            else
              "rm"
            end

            args = if any_receiver_rmtree?(node)
              node.receiver&.source || node.arguments.first&.source
            else
              node.arguments.first.source
            end
            args = "(#{args})" unless args.start_with?("(")
            corrector.replace(node.loc.expression, "#{class_name}#{new_method}#{args}")
          end
        end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def neither_rm_rf_nor_rmtree?(node)
          !any_receiver_rm_r_f?(node) && !no_receiver_rm_r_f?(node) &&
            !any_receiver_rmtree?(node) && !no_receiver_rmtree?(node)
        end
      end
    end
  end
end
