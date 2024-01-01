# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits the service block.
      #
      # @api private
      class Service < FormulaCop
        extend AutoCorrector

        CELLAR_PATH_AUDIT_CORRECTIONS = {
          bin:      :opt_bin,
          libexec:  :opt_libexec,
          pkgshare: :opt_pkgshare,
          prefix:   :opt_prefix,
          sbin:     :opt_sbin,
          share:    :opt_share,
        }.freeze

        # At least one of these methods must be defined in a service block.
        REQUIRED_METHOD_CALLS = [:run, :name].freeze

        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          service_node = find_block(body_node, :service)
          return if service_node.blank?

          method_calls = service_node.each_descendant(:send).group_by(&:method_name)
          method_calls.delete(:service)

          # NOTE: Solving the first problem here might solve the second one too
          # so we don't show both of them at the same time.
          if (method_calls.keys & REQUIRED_METHOD_CALLS).empty?
            offending_node(service_node)
            problem "Service blocks require `run` or `name` to be defined."
          elsif !method_calls.key?(:run)
            other_method_calls = method_calls.keys - [:name]
            if other_method_calls.any?
              offending_node(service_node)
              problem "`run` must be defined to use methods other than `name` like #{other_method_calls}."
            end
          end

          # This check ensures that cellar paths like `bin` are not referenced
          # because their `opt_` variants are more portable and work with the API.
          CELLAR_PATH_AUDIT_CORRECTIONS.each do |path, opt_path|
            next unless method_calls.key?(path)

            method_calls.fetch(path).each do |node|
              offending_node(node)
              problem "Use `#{opt_path}` instead of `#{path}` in service blocks." do |corrector|
                corrector.replace(node.source_range, opt_path)
              end
            end
          end
        end
      end
    end
  end
end
