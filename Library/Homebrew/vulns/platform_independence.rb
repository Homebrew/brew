# typed: strict
# frozen_string_literal: true

require "prism"

module Homebrew
  module Vulns
    # Proves independence of the metadata read by Match, not of installation.
    # Unknown Ruby or DSL is deliberately evaluated separately on each platform.
    module PlatformIndependence
      SOURCE_CALLS = [:url, :mirror, :version, :sha256, :sha1, :md5].freeze
      FORMULA_CALLS = T.let((SOURCE_CALLS + [
        :desc, :homepage, :head, :revision, :version_scheme, :license, :depends_on,
        :uses_from_macos, :keg_only, :conflicts_with, :option, :deprecated_option,
        :deprecate!, :disable!, :pypi_packages
      ]).freeze, T::Array[Symbol])

      sig { params(formula: Formula).returns(T::Boolean) }
      def self.formula?(formula)
        source?(Formulary.formula_contents(formula.path))
      rescue SystemCallError
        false
      end

      sig { params(source: String).returns(T::Boolean) }
      def self.source?(source)
        parsed = Prism.parse(source)
        return false unless parsed.success?

        statements = parsed.value.statements.body
        definition = statements.first
        return false if !statements.one? || !definition.is_a?(Prism::ClassNode)
        return false unless definition.constant_path.is_a?(Prism::ConstantReadNode)

        parent = definition.superclass
        return false if !parent.is_a?(Prism::ConstantReadNode) || parent.name != :Formula

        body?(definition.body, :formula)
      end

      sig { params(body: T.nilable(Prism::Node), context: Symbol).returns(T::Boolean) }
      def self.body?(body, context)
        return true if body.nil?
        return false unless body.is_a?(Prism::StatementsNode)

        body.body.all? do |node|
          # These methods and Formula.test's block are stored, never invoked by
          # loading or matching. No arbitrary helpers or metadata overrides.
          if context == :formula && node.is_a?(Prism::DefNode)
            next node.receiver.nil? && node.parameters.nil? && [:install, :post_install, :caveats].include?(node.name)
          end
          next false if !node.is_a?(Prism::CallNode) || !node.receiver.nil?

          arguments = node.arguments&.arguments || []
          block = node.block
          if context == :formula && node.name == :include && block.nil?
            # This mixin defines installation helpers only, with no included hook.
            next arguments.one? && arguments.first&.location&.slice == "Language::Python::Virtualenv"
          end
          next false unless arguments.all? { |argument| literal?(argument) }

          if block
            next false if !block.is_a?(Prism::BlockNode) || !block.parameters.nil?
            next true if context == :formula && node.name == :test && arguments.empty?

            nested = case node.name
            when :stable, :head then :source if context == :formula && arguments.empty?
            when :bottle then :bottle if context == :formula && arguments.empty?
            when :resource
              :resource if [:formula, :source].include?(context) && arguments.one? &&
                           arguments.first.is_a?(Prism::StringNode)
            when :patch then :patch if [:formula, :source, :resource].include?(context)
            end
            next false unless nested

            body?(block.body, nested)
          else
            allowed = case context
            when :formula then FORMULA_CALLS
            when :source then SOURCE_CALLS + [:depends_on, :uses_from_macos, :option]
            when :resource then SOURCE_CALLS
            when :patch then SOURCE_CALLS + [:resolves, :apply]
            when :bottle then [:sha256, :sha1, :root_url, :cellar, :prefix, :rebuild]
            else []
            end
            allowed.include?(node.name)
          end
        end
      end

      sig { params(node: Prism::Node).returns(T::Boolean) }
      def self.literal?(node)
        case node
        when Prism::StringNode, Prism::SymbolNode, Prism::IntegerNode, Prism::FloatNode,
             Prism::TrueNode, Prism::FalseNode, Prism::NilNode
          true
        when Prism::ArrayNode
          node.elements.all? { |element| literal?(element) }
        when Prism::HashNode, Prism::KeywordHashNode
          node.elements.all? do |element|
            element.is_a?(Prism::AssocNode) && literal?(element.key) && literal?(element.value)
          end
        else
          false
        end
      end
      private_class_method :body?, :literal?
    end
  end
end
