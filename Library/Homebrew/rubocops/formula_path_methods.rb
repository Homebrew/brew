# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Checks for formula instances created only to build stable opt paths.
      class FormulaPathMethods < Base
        extend AutoCorrector

        FORMULA_OPT_HELPERS = T.let({
          opt_bin:     "formula_opt_bin",
          opt_lib:     "formula_opt_lib",
          opt_libexec: "formula_opt_libexec",
          opt_include: "formula_opt_include",
          opt_prefix:  "formula_opt_prefix",
        }.freeze, T::Hash[Symbol, String])
        SCOPED_FORMULA_HELPERS = [
          :formula_any_version_installed?,
          :formula_opt_bin,
          :formula_opt_include,
          :formula_opt_lib,
          :formula_opt_libexec,
          :formula_opt_prefix,
        ].freeze

        MSG = "Use `%<preferred>s` instead of `%<current>s`."
        RESTRICT_ON_SEND = T.let([
          :any_version_installed?,
          :installed?,
          :installed_version,
          :opt_bin,
          :opt_include,
          :opt_lib,
          :opt_libexec,
          :opt_prefix,
          *SCOPED_FORMULA_HELPERS,
        ].freeze, T::Array[Symbol])

        def_node_matcher :formula_lookup_name_node, <<~PATTERN
          (send (const {nil? cbase} :Formula) :[] $_)
        PATTERN

        def_node_matcher :formula_path_name_node, <<~PATTERN
          {
            (send (const {nil? cbase} :Formula) :[] $_)
            (send (const {nil? cbase} :Formulary) :factory $_)
          }
        PATTERN

        def_node_matcher :cask_new_token_node, <<~PATTERN
          (send (const (const {nil? cbase} :Cask) :Cask) :new $_ ...)
        PATTERN

        def_node_matcher :formula_class?, <<~PATTERN
          (class _ (const {nil? cbase} :Formula) ...)
        PATTERN

        def_node_matcher :utils_path?, <<~PATTERN
          (const (const {nil? cbase} :Utils) :Path)
        PATTERN

        def_node_matcher :cask_block?, <<~PATTERN
          (block (send nil? :cask ...) ...)
        PATTERN

        def_node_matcher :service_block?, <<~PATTERN
          (block (send nil? :service) ...)
        PATTERN

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          preferred = preferred_method_call(node)
          return unless preferred

          add_offense(node, message: format(MSG, preferred:, current: node.source)) do |corrector|
            corrector.replace(node.loc.expression, preferred)
          end
        end

        private

        sig { params(node: RuboCop::AST::SendNode).returns(T.nilable(String)) }
        def preferred_method_call(node)
          case node.method_name
          when :any_version_installed?
            return if node.each_ancestor.any?(&:rescue_type?)

            formula_lookup_name_node(node.receiver) do |formula_name|
              return unless formula_name.str_type?

              return formula_helper_method_call("formula_any_version_installed?", formula_name, node)
            end
            cask_new_token_node(node.receiver) do |cask_token|
              return "Cask::Caskroom.cask_installed?(#{cask_token.source})"
            end
          when :installed?
            cask_new_token_node(node.receiver) do |cask_token|
              return "Cask::Caskroom.cask_installed?(#{cask_token.source})"
            end
          when :installed_version
            cask_new_token_node(node.receiver) do |cask_token|
              return "Cask::Caskroom.cask_installed_version(#{cask_token.source})"
            end
          when *SCOPED_FORMULA_HELPERS
            receiver = node.receiver
            return unless receiver
            return unless utils_path?(receiver)
            return unless node.each_ancestor.any? { |ancestor| service_block?(ancestor) }

            return "#{node.method_name}(#{node.arguments.map(&:source).join(", ")})"
          else
            return if node.each_ancestor.any?(&:rescue_type?)

            formula_path_name_node(node.receiver) do |formula_name|
              return formula_helper_method_call(FORMULA_OPT_HELPERS.fetch(node.method_name), formula_name, node)
            end
          end
          nil
        end

        sig { params(helper_method: String, formula_name: RuboCop::AST::Node, node: RuboCop::AST::Node).returns(String) }
        def formula_helper_method_call(helper_method, formula_name, node)
          helper_receiver = "Utils::Path." unless formula_or_cask_dsl?(node)
          "#{helper_receiver}#{helper_method}(#{formula_name.source})"
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def formula_or_cask_dsl?(node)
          node.each_ancestor.any? { |ancestor| formula_class?(ancestor) || cask_block?(ancestor) }
        end
      end
    end
  end
end
