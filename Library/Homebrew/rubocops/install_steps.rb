# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"
require "rubocops/shared/install_steps_helper"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks declarative install step usage.
      class InstallSteps < FormulaCop
        extend AutoCorrector
        include InstallStepsHelper

        # TODO: Re-enable when formula `post_install` and `post_install_steps`
        # cannot coexist after the incremental conversion bridge is removed.
        # CONFLICT_MSG = "`post_install` and `post_install_steps` cannot both be used."
        POST_INSTALL_STEPS_ORDER_MSG = "`post_install_steps` must appear before `post_install` to match run order."
        REDUNDANT_SERVICE_PATH_DIRS_MSG = "`%<block>s` only creates directories created by `brew services`."

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          service_path_dirs = service_path_dirs(find_block(body_node, :service))
          post_install_steps_block = find_block(body_node, :post_install_steps)
          post_install_method = find_method_def(body_node, :post_install)

          # TODO: Re-enable when formula `post_install` and
          # `post_install_steps` cannot coexist after the incremental
          # conversion bridge is removed.
          # if post_install_steps_block && post_install_method
          #   offending_node(post_install_steps_block)
          #   problem CONFLICT_MSG
          # end

          add_post_install_steps_order_offense(post_install_steps_block, post_install_method)
          audit_step_block(post_install_steps_block)
          add_redundant_service_path_dirs_offense(post_install_steps_block, service_path_dirs, :post_install_steps)
          redundant_post_install = post_install_method.present? &&
                                   redundant_service_path_dirs_block?(post_install_method, service_path_dirs,
                                                                      :post_install)
          add_redundant_service_path_dirs_offense(post_install_method, service_path_dirs, :post_install)
          audit_post_install_method(post_install_method) if post_install_steps_block.nil? && !redundant_post_install
        end

        private

        sig {
          params(
            post_install_steps_block: T.nilable(RuboCop::AST::BlockNode),
            post_install_method:      T.nilable(RuboCop::AST::Node),
          ).void
        }
        def add_post_install_steps_order_offense(post_install_steps_block, post_install_method)
          return if post_install_steps_block.nil? || post_install_method.nil?
          return if post_install_steps_block.loc.line < post_install_method.loc.line

          offending_node(post_install_steps_block)
          problem POST_INSTALL_STEPS_ORDER_MSG
        end

        sig { params(block_node: T.nilable(RuboCop::AST::BlockNode)).void }
        def audit_step_block(block_node)
          return unless (offense_node = install_step_block_offense_node(block_node))

          offending_node(offense_node)
          problem STEP_BLOCK_MSG
        end

        sig { params(post_install_method: T.nilable(RuboCop::AST::Node)).void }
        def audit_post_install_method(post_install_method)
          return if post_install_method.nil?
          return unless post_install_method.def_type?

          post_install_def = T.cast(post_install_method, RuboCop::AST::DefNode)
          step_lines = simple_install_step_lines(post_install_def.body,
                                                 default_base:        :var,
                                                 default_source_base: :prefix,
                                                 default_target_base: :prefix)
          return if step_lines.blank?

          add_offense(post_install_method,
                      message: format(SIMPLE_STEP_CONVERSION_MSG, steps_block: "post_install_steps")) do |corrector|
            corrector.replace(
              post_install_method.source_range,
              install_steps_block_source(:post_install_steps, step_lines, post_install_method.source_range.column),
            )
          end
        end

        sig {
          params(
            node:              T.nilable(RuboCop::AST::Node),
            service_path_dirs: T::Array[InstallStepPath],
            block_name:        Symbol,
          ).void
        }
        def add_redundant_service_path_dirs_offense(node, service_path_dirs, block_name)
          return if node.nil? || service_path_dirs.empty?
          return unless redundant_service_path_dirs_block?(node, service_path_dirs, block_name)

          add_offense(node, message: format(REDUNDANT_SERVICE_PATH_DIRS_MSG, block: block_name)) do |corrector|
            corrector.remove(range_with_surrounding_space(range: node.source_range, side: :left))
          end
        end

        sig {
          params(
            node:              RuboCop::AST::Node,
            service_path_dirs: T::Array[InstallStepPath],
            block_name:        Symbol,
          ).returns(T::Boolean)
        }
        def redundant_service_path_dirs_block?(node, service_path_dirs, block_name)
          body = if node.def_type?
            T.cast(node, RuboCop::AST::DefNode).body
          elsif node.block_type?
            T.cast(node, RuboCop::AST::BlockNode).body
          end
          return false if body.nil?

          direct_nodes = body.begin_type? ? body.child_nodes : [body]
          direct_nodes.all? do |direct_node|
            service_path_dirs.any? do |path_dir|
              redundant_service_path_dir?(direct_node, path_dir, block_name)
            end
          end
        end

        sig {
          params(
            node:       RuboCop::AST::Node,
            path_dir:   InstallStepPath,
            block_name: Symbol,
          ).returns(T::Boolean)
        }
        def redundant_service_path_dir?(node, path_dir, block_name)
          return false unless node.send_type?

          send_node = T.cast(node, RuboCop::AST::SendNode)
          path = if block_name == :post_install && send_node.method_name == :mkpath && send_node.arguments.empty?
            install_step_path(send_node.receiver)
          else
            return false unless [:mkdir, :mkdir_p].include?(send_node.method_name)

            fileutils_receiver = block_name == :post_install &&
                                 send_node.receiver&.const_type? &&
                                 send_node.receiver&.const_name == "FileUtils"
            return false if send_node.receiver.present? && !fileutils_receiver

            install_step_path_with_base(send_node.arguments.first, send_node.last_argument, default_base: :var)
          end
          paths_match?(path, path_dir)
        end

        sig { params(block_node: T.nilable(RuboCop::AST::BlockNode)).returns(T::Array[InstallStepPath]) }
        def service_path_dirs(block_node)
          return [] if block_node.nil?

          body = block_node.body
          return [] if body.nil?

          direct_nodes = body.begin_type? ? body.child_nodes : [body]
          paths = direct_nodes.filter_map do |node|
            next unless node.send_type?

            send_node = T.cast(node, RuboCop::AST::SendNode)
            next if send_node.receiver.present? || send_node.arguments.empty?

            path = install_step_path(send_node.arguments.first)
            case send_node.method_name
            when :working_dir, :root_dir
              path
            when :input_path, :log_path, :error_log_path
              path_parent(path)
            end
          end
          paths.uniq { |path| path_key(path) }
        end

        sig {
          params(
            node:         T.nilable(RuboCop::AST::Node),
            last_arg:     T.nilable(RuboCop::AST::Node),
            default_base: Symbol,
          ).returns(T.nilable(InstallStepPath))
        }
        def install_step_path_with_base(node, last_arg, default_base:)
          path = install_step_path(node)
          return if path.nil?

          base = install_step_path_hash_base(last_arg)
          return InstallStepPath.new(path: path.path, base:) if base
          if path.base.nil? && !absolute_install_step_path?(path)
            return InstallStepPath.new(path: path.path,
                                       base: default_base)
          end

          path
        end

        sig { params(node: T.nilable(RuboCop::AST::Node)).returns(T.nilable(Symbol)) }
        def install_step_path_hash_base(node)
          return unless node&.hash_type?

          T.cast(node, RuboCop::AST::HashNode).pairs.each do |pair|
            key = pair.key
            next unless key.sym_type?
            next if T.cast(key, RuboCop::AST::SymbolNode).value != :base

            value = pair.value
            return T.cast(value, RuboCop::AST::SymbolNode).value if value.sym_type?
          end
          nil
        end

        sig { params(path: T.nilable(InstallStepPath)).returns(T.nilable(InstallStepPath)) }
        def path_parent(path)
          return if path.nil?

          parent_path = Pathname.new(path.path).dirname.to_s
          return if parent_path == "."

          InstallStepPath.new(path: parent_path, base: path.base)
        end

        sig { params(path: T.nilable(InstallStepPath), other_path: InstallStepPath).returns(T::Boolean) }
        def paths_match?(path, other_path)
          return false if path.nil?

          path_key(path) == path_key(other_path)
        end

        sig { params(path: InstallStepPath).returns([T.nilable(Symbol), String]) }
        def path_key(path)
          [path.base, path.path]
        end
      end
    end
  end
end
