# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits Python formulae that include certain resources
      # to ensure that they also have the correct `uses_from_macos`
      # dependencies.
      class ResourceRequiresDependencies < FormulaCop
        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          return if body_node.nil?

          resource_nodes = find_every_method_call_by_name(body_node, :resource)
          return if resource_nodes.empty?

          %w[lxml pyyaml].each do |resource_name|
            found = resource_nodes.find { |node| node.arguments&.first&.str_content == resource_name }
            next unless found

            uses_from_macos_nodes = find_every_method_call_by_name(body_node, :uses_from_macos)
            uses_from_macos = uses_from_macos_nodes.map { |node| node.arguments.first.str_content }

            depends_on_nodes = find_every_method_call_by_name(body_node, :depends_on)
            depends_on = depends_on_nodes.map { |node| node.arguments.first.str_content }

            required_deps = case resource_name
            when "lxml"
              kind = "uses_from_macos"
              ["libxml2", "libxslt"]
            when "pyyaml"
              kind = "depends_on"
              ["libyaml"]
            else
              []
            end
            next if required_deps.all? { |dep| uses_from_macos.include?(dep) || depends_on.include?(dep) }

            offending_node(found)
            problem "Add `#{kind}` lines above for #{required_deps.map { |req| "`\"#{req}\"`" }.join(" and ")}."
          end
        end
      end
    end
  end
end
