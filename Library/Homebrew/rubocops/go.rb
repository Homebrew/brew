# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks for Go-related problems in formulae.
      #
      # @api private
      class Go < FormulaCop
        extend AutoCorrector

        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          unless method_called_ever?(body_node, :go_resource)
            # processed_source.ast is passed instead of body_node because `require` would be outside body_node
            find_method_with_args(processed_source.ast, :require, "language/go") do
              problem "require \"language/go\" is unnecessary unless using `go_resource`s"
            end
          end

          find_method_with_args(body_node, :system, "go", "get") do
            problem "Do not use `go get`. Please ask upstream to implement Go vendoring"
          end

          find_method_with_args(body_node, :system, "dep", "ensure") do |d|
            next if parameters_passed?(d, /vendor-only/)

            problem "use \"dep\", \"ensure\", \"-vendor-only\""
          end

          find_every_method_call_by_name(body_node, :system).each do |m|
            method_params = parameters(m)

            next unless node_equals?(method_params.first, "go")
            next unless node_equals?(method_params.second, "build")

            std_go_args_node = method_params.find do |param|
              next false unless param.splat_type?

              child = param.children.first
              next false unless child.send_type?

              child.method_name == :std_go_args
            end

            if std_go_args_node.nil?
              offending_node(m)
              problem "`*std_go_args` should be passed to `go build`" do |corrector|
                corrector.insert_after(method_params.second.loc.expression, ", *std_go_args")

                o_range, o_source = get_arg_range_and_value_source(method_params, "o")
                remove_arg(corrector, o_range) if o_source&.match?(%r{^"?bin/"?#{Regexp.escape(@formula_name)}"$})

                trimpath_node = method_params.find { |param| string_content(param) == "-trimpath" }
                remove_arg(corrector, trimpath_node.loc.expression) if trimpath_node
              end
            else
              range, ldflags = get_arg_range_and_value_source(method_params, "ldflags")
              next if range.nil?

              add_offense(range, message: "use the `ldflags` argument of `std_go_args`") do |corrector|
                remove_arg(corrector, range)
                corrector.replace(std_go_args_node.loc.expression,
                                  "*std_go_args(ldflags: #{ldflags})")
              end
            end
          end
        end

        private

        def get_arg_range_and_value_source(method_params, flag)
          index = method_params.index do |param|
            string_content(param).match?(/^-#{Regexp.escape(flag)}(=|$)/)
          end
          return if index.nil?

          node = method_params[index]
          begin_pos = node.loc.expression.begin_pos

          if string_content(node) == "-#{flag}"
            second_node = method_params[index + 1]
            end_pos = second_node.loc.expression.end_pos
            source = second_node.source
          else
            end_pos = node.loc.expression.end_pos
            source = "\"#{string_content(node).delete_prefix("-#{flag}")}\""
          end

          [range_between(begin_pos, end_pos), source]
        end

        def remove_arg(corrector, range)
          range = range_with_surrounding_space(range: range, side: :left)
          range = range_with_surrounding_comma(range, :left)
          corrector.remove(range)
        end
      end
    end

    module FormulaAuditStrict
      # This cop contains stricter checks for Go-related problems in formulae.
      #
      # @api private
      class Go < FormulaCop
        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          find_method_with_args(body_node, :go_resource) do
            problem "`go_resource`s are deprecated. Please ask upstream to implement Go vendoring"
          end
        end
      end
    end
  end
end
