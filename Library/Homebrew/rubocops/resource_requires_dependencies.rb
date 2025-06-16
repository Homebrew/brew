# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits Python formulae that include certain resources
      # to ensure that they also have the correct `uses_from_macos`
      # dependencies.
      class ResourceRequiresDependencies < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          resource_nodes = find_every_method_call_by_name(body_node, :resource)
          return if resource_nodes.empty?

          %w[lxml pyyaml].each do |resource_name|
            found = resource_nodes.find { |node| node.arguments&.first&.str_content == resource_name }
            next unless found

            uses_from_macos_nodes = find_every_method_call_by_name(body_node, :uses_from_macos)
            depends_on_nodes = find_every_method_call_by_name(body_node, :depends_on)
            uses_from_macos_or_depends_on = (uses_from_macos_nodes + depends_on_nodes).filter_map do |node|
              if (dep = node.arguments.first).hash_type?
                dep_types = dep.values.first
                dep_types = dep_types.array_type? ? dep_types.values : [dep_types]
                dep.keys.first.str_content if dep_types.select(&:sym_type?).map(&:value).include?(:build)
              else
                dep.str_content
              end
            end

            required_deps = case resource_name
            when "lxml"
              kind = depends_on?(:linux) ? "depends_on" : "uses_from_macos"
              ["libxml2", "libxslt"]
            when "pyyaml"
              kind = "depends_on"
              ["libyaml"]
            else
              []
            end
            next if required_deps.all? { |dep| uses_from_macos_or_depends_on.include?(dep) }

            offending_node(found)
            problem "Add `#{kind}` lines above for #{required_deps.map { |req| "`\"#{req}\"`" }.join(" and ")}."
          end
        end
      end
    end
  end
end
