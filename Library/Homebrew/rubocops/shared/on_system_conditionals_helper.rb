# typed: strict
# frozen_string_literal: true

require "macos_version"
require "rubocops/shared/helper_functions"

module RuboCop
  module Cop
    # This module performs common checks on `on_{system}` blocks in both formulae and casks.
    module OnSystemConditionalsHelper
      extend NodePattern::Macros
      include HelperFunctions

      ARCH_OPTIONS = [:arm, :intel].freeze
      BASE_OS_OPTIONS = [:macos, :linux].freeze
      MACOS_VERSION_OPTIONS = T.let(MacOSVersion::SYMBOLS.keys.freeze, T::Array[Symbol])
      ON_SYSTEM_OPTIONS = T.let(
        [*ARCH_OPTIONS, *BASE_OS_OPTIONS, *MACOS_VERSION_OPTIONS, :system].freeze,
        T::Array[Symbol],
      )
      MACOS_MODULE_NAMES = ["MacOS", "OS::Mac"].freeze

      MACOS_VERSION_CONDITIONALS = T.let(
        {
          "==" => nil,
          "<=" => :or_older,
          ">=" => :or_newer,
        }.freeze,
        T::Hash[String, T.nilable(Symbol)],
      )

      sig { params(body_node: RuboCop::AST::Node, parent_name: Symbol).void }
      def audit_on_system_blocks(body_node, parent_name)
        parent_string = if body_node.def_type?
          "def #{parent_name}"
        else
          "#{parent_name} do"
        end

        ON_SYSTEM_OPTIONS.each do |on_system_option|
          on_system_method = :"on_#{on_system_option}"
          if_statement_string = if ARCH_OPTIONS.include?(on_system_option)
            "if Hardware::CPU.#{on_system_option}?"
          elsif BASE_OS_OPTIONS.include?(on_system_option)
            "if OS.#{(on_system_option == :macos) ? "mac" : "linux"}?"
          elsif on_system_option == :system
            "if OS.linux? || MacOS.version"
          else
            "if MacOS.version"
          end

          find_every_method_call_by_name(body_node, on_system_method).each do |on_system_node|
            if_conditional = ""
            if MACOS_VERSION_OPTIONS.include? on_system_option
              on_macos_version_method_call(on_system_node, on_method: on_system_method) do |on_method_parameters|
                if on_method_parameters.empty?
                  if_conditional = " == :#{on_system_option}"
                else
                  if_condition_operator = MACOS_VERSION_CONDITIONALS.key(on_method_parameters.first)
                  if_conditional = " #{if_condition_operator} :#{on_system_option}"
                end
              end
            elsif on_system_option == :system
              on_system_method_call(on_system_node) do |macos_symbol|
                base_os, condition = macos_symbol.to_s.split(/_(?=or_)/).map(&:to_sym)
                if_condition_operator = MACOS_VERSION_CONDITIONALS.key(condition)
                if_conditional = " #{if_condition_operator} :#{base_os}"
              end
            end

            offending_node(on_system_node)
            problem "Don't use `#{on_system_node.source}` in `#{parent_string}`, " \
                    "use `#{if_statement_string}#{if_conditional}` instead." do |corrector|
              block_node = offending_node.parent
              next if block_node.type != :block

              # TODO: could fix corrector to handle this but punting for now.
              next if block_node.single_line?

              source_range = offending_node.source_range.join(offending_node.parent.loc.begin)
              corrector.replace(source_range, "#{if_statement_string}#{if_conditional}")
            end
          end
        end
      end

      sig {
        params(
          body_node: RuboCop::AST::Node, allowed_methods: T::Array[Symbol],
          allowed_blocks: T::Array[Symbol]
        ).void
      }
      def audit_arch_conditionals(body_node, allowed_methods: [], allowed_blocks: [])
        ARCH_OPTIONS.each do |arch_option|
          else_method = (arch_option == :arm) ? :on_intel : :on_arm
          if_arch_node_search(body_node, arch: :"#{arch_option}?") do |if_node, else_node|
            next if node_is_allowed?(if_node, allowed_methods:, allowed_blocks:)

            if_statement_problem(if_node, "if Hardware::CPU.#{arch_option}?", "on_#{arch_option}",
                                 else_method:, else_node:)
          end
        end

        [:arch, :arm?, :intel?].each do |method|
          hardware_cpu_search(body_node, method:) do |method_node|
            # These should already be caught by `if_arch_node_search`
            next if method_node.parent.source.start_with? "if #{method_node.source}"
            next if node_is_allowed?(method_node, allowed_methods:, allowed_blocks:)

            offending_node(method_node)
            problem "Don't use `#{method_node.source}`, use `on_arm` and `on_intel` blocks instead."
          end
        end
      end

      sig {
        params(
          body_node: RuboCop::AST::Node, allowed_methods: T::Array[Symbol],
          allowed_blocks: T::Array[Symbol]
        ).void
      }
      def audit_base_os_conditionals(body_node, allowed_methods: [], allowed_blocks: [])
        BASE_OS_OPTIONS.each do |base_os_option|
          os_method, else_method = if base_os_option == :macos
            [:mac?, :on_linux]
          else
            [:linux?, :on_macos]
          end
          if_base_os_node_search(body_node, base_os: os_method) do |if_node, else_node|
            next if node_is_allowed?(if_node, allowed_methods:, allowed_blocks:)

            if_statement_problem(if_node, "if OS.#{os_method}", "on_#{base_os_option}",
                                 else_method:, else_node:)
          end
        end
      end

      sig {
        params(
          body_node:           RuboCop::AST::Node,
          allowed_methods:     T::Array[Symbol],
          allowed_blocks:      T::Array[Symbol],
          recommend_on_system: T::Boolean,
        ).void
      }
      def audit_macos_version_conditionals(body_node, allowed_methods: [], allowed_blocks: [],
                                           recommend_on_system: true)
        MACOS_VERSION_OPTIONS.each do |macos_version_option|
          if_macos_version_node_search(body_node, os_version: macos_version_option) do |if_node, operator, else_node|
            next if node_is_allowed?(if_node, allowed_methods:, allowed_blocks:)

            else_node = T.let(else_node, T.nilable(RuboCop::AST::Node))
            autocorrect = else_node.blank? && MACOS_VERSION_CONDITIONALS.key?(operator.to_s)
            on_system_method_string = if recommend_on_system && operator == :<
              "on_system"
            elsif recommend_on_system && operator == :<=
              "on_system :linux, macos: :#{macos_version_option}_or_older"
            elsif operator != :== && MACOS_VERSION_CONDITIONALS.key?(operator.to_s)
              "on_#{macos_version_option} :#{MACOS_VERSION_CONDITIONALS[operator.to_s]}"
            else
              "on_#{macos_version_option}"
            end

            if_statement_problem(if_node, "if MacOS.version #{operator} :#{macos_version_option}",
                                 on_system_method_string, autocorrect:)
          end

          macos_version_comparison_search(body_node, os_version: macos_version_option) do |method_node|
            # These should already be caught by `if_macos_version_node_search`
            next if method_node.parent.source.start_with? "if #{method_node.source}"
            next if node_is_allowed?(method_node, allowed_methods:, allowed_blocks:)

            offending_node(method_node)
            problem "Don't use `#{method_node.source}`, use `on_{macos_version}` blocks instead."
          end
        end
      end

      sig {
        params(
          body_node:       RuboCop::AST::Node,
          allowed_methods: T::Array[Symbol],
          allowed_blocks:  T::Array[Symbol],
        ).void
      }
      def audit_macos_references(body_node, allowed_methods: [], allowed_blocks: [])
        MACOS_MODULE_NAMES.each do |macos_module_name|
          find_const(body_node, macos_module_name) do |node|
            next if node_is_allowed?(node, allowed_methods:, allowed_blocks:)

            offending_node(node)
            problem "Don't use `#{macos_module_name}` where it could be called on Linux."
          end
        end
      end

      private

      sig {
        params(
          if_node:                 RuboCop::AST::IfNode,
          if_statement_string:     String,
          on_system_method_string: String,
          else_method:             T.nilable(Symbol),
          else_node:               T.nilable(RuboCop::AST::Node),
          autocorrect:             T::Boolean,
        ).void
      }
      def if_statement_problem(if_node, if_statement_string, on_system_method_string,
                               else_method: nil, else_node: nil, autocorrect: true)
        offending_node(if_node)
        problem "Don't use `#{if_statement_string}`, " \
                "use `#{on_system_method_string} do` instead." do |corrector|
          next unless autocorrect
          # TODO: could fix corrector to handle this but punting for now.
          next if if_node.unless?

          if else_method.present? && else_node.present?
            corrector.replace(if_node.source_range,
                              "#{on_system_method_string} do\n#{if_node.body.source}\nend\n" \
                              "#{else_method} do\n#{else_node.source}\nend")
          else
            corrector.replace(if_node.source_range, "#{on_system_method_string} do\n#{if_node.body.source}\nend")
          end
        end
      end

      sig {
        params(
          node: RuboCop::AST::Node, allowed_methods: T::Array[Symbol],
          allowed_blocks: T::Array[Symbol]
        ).returns(T::Boolean)
      }
      def node_is_allowed?(node, allowed_methods: [], allowed_blocks: [])
        # TODO: check to see if it's legal
        valid = T.let(false, T::Boolean)
        node.each_ancestor do |ancestor|
          valid_method_names = case ancestor.type
          when :def
            allowed_methods
          when :block
            allowed_blocks
          else
            next
          end
          next unless valid_method_names.include?(ancestor.method_name)

          valid = true
          break
        end
        return true if valid

        false
      end

      def_node_matcher :on_macos_version_method_call, <<~PATTERN
        (send nil? %on_method (sym ${:or_newer :or_older})?)
      PATTERN

      def_node_matcher :on_system_method_call, <<~PATTERN
        (send nil? :on_system (sym :linux) (hash (pair (sym :macos) (sym $_))))
      PATTERN

      def_node_search :hardware_cpu_search, <<~PATTERN
        (send (const (const nil? :Hardware) :CPU) %method)
      PATTERN

      def_node_search :macos_version_comparison_search, <<~PATTERN
        (send (send (const nil? :MacOS) :version) {:== :<= :< :>= :> :!=} (sym %os_version))
      PATTERN

      def_node_search :if_arch_node_search, <<~PATTERN
        $(if (send (const (const nil? :Hardware) :CPU) %arch) _ $_)
      PATTERN

      def_node_search :if_base_os_node_search, <<~PATTERN
        $(if (send (const nil? :OS) %base_os) _ $_)
      PATTERN

      def_node_search :if_macos_version_node_search, <<~PATTERN
        $(if (send (send (const nil? :MacOS) :version) ${:== :<= :< :>= :> :!=} (sym %os_version)) _ $_)
      PATTERN
    end
  end
end
