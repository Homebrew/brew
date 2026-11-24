# typed: strict
# frozen_string_literal: true

require "digest"

module RuboCop
  module Cop
    module Homebrew
      # Checks for methods that are only called once and so can be inlined into their caller.
      #
      # Formula classes are self-contained, so only references in the same file are counted.
      # Elsewhere, only non-public methods are checked and the project index must contain no other
      # definition of or reference to the method name, including a symbol or symbol hash key. Indexed
      # files with identical contents, e.g. a symlink or copy of a tap, count once.
      #
      # Any other mention of the method name in the file, e.g. a symbol passed to `send` or the
      # name inside a string, counts as a reference.
      #
      # Methods using `return`, `yield`, `super`, `on_*` blocks, memoisation or a block parameter are
      # skipped as they cannot be moved into their caller unchanged. So are methods with a `rescue` or
      # `ensure` called in a condition or rescuing into a variable name the caller already uses, and
      # methods whose enclosing methods or blocks would then exceed an enabled `Metrics` length,
      # ABC size, complexity or nesting limit.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # def install
      #   system "make", *make_args
      # end
      #
      # def make_args
      #   ["PREFIX=#{prefix}"]
      # end
      #
      # # good
      # def install
      #   system "make", "PREFIX=#{prefix}"
      # end
      # ```
      class SingleUseMethod < Base
        include ProjectIndexHelp

        MSG = "Inline `%<method>s` into its only caller."
        IDENTIFIER_PATTERN = /[a-zA-Z_]\w*[?!=]?/
        NAME_PREFIX_PATTERN = /[a-zA-Z_]\w*\z/
        # A symbol, e.g. `receive(:name)`, or a symbol hash key, e.g. `receive_messages(name: value)`.
        SYMBOL_PATTERN = /(?<![:\w]):"?([a-zA-Z_]\w*[?!=]?)|(?<![:\w])([a-zA-Z_]\w*[?!]?):(?!:)/
        # Homebrew also calls these formula methods by name, so they must stay methods.
        FORMULA_HOOK_METHODS = [:caveats, :fetch, :install, :post_install, :test].freeze

        # Expose RuboCop's own complexity scoring so inlining is checked against the same limits.
        class CyclomaticComplexityScore < Metrics::CyclomaticComplexity
          exclude_from_registry
          public :complexity, :reset_repeated_csend
        end

        class PerceivedComplexityScore < Metrics::PerceivedComplexity
          exclude_from_registry
          public :complexity, :reset_repeated_csend
        end

        class BlockNestingScore < Metrics::BlockNesting
          exclude_from_registry
          public :consider_node?, :count_if_block?

          # Read e.g. `CountModifierForms` from `Metrics/BlockNesting` rather than this class's own badge.
          sig { returns(T::Hash[String, T.anything]) }
          def cop_config = config.for_cop("Metrics/BlockNesting")
        end

        class << self
          # Counting names across the project index is shared by every file checked against it.
          sig {
            returns(T.nilable([Rubydex::Graph, T::Hash[String, Integer], T::Hash[String, Integer], T::Set[String]]))
          }
          attr_accessor :cached_index_name_counts
        end

        # These cannot be moved into the caller unchanged: `return`, `yield`, `super` and `block_given?`
        # would act on the caller, `FormulaAudit/OnSystemConditionals` disallows `on_*` blocks in e.g.
        # `install` and memoised values are kept between calls, e.g. from a loop.
        def_node_search :unmovable?, <<~PATTERN
          {return yield super zsuper (send _ :block_given?) (or_asgn ivasgn _) (any_block (call _ /^on_/ ...) ...)}
        PATTERN

        def_node_search :rescued_variable_names, "(resbody _ (lvasgn $_) _)"

        def_node_matcher :formula_class?, "(class _ (const _ :Formula) _)"

        sig { params(node: RuboCop::AST::DefNode).void }
        def on_def(node)
          return if node.each_ancestor(:any_def, :any_block, :sclass).any?
          # A block parameter has no equivalent once the method is inlined.
          return if node.block_argument? || unmovable?(node)

          namespace = node.each_ancestor(:class, :module).first
          return if namespace.nil?
          return if FORMULA_HOOK_METHODS.include?(node.method_name) && formula_class?(namespace)

          name = node.method_name
          references = processed_source.ast&.each_node(:call, :def, :sym, :str, :dstr, :dsym)&.select do |reference|
            next false if reference.equal?(node)

            # Matching raises on string literals with invalid byte sequences, hence `scrub`.
            case reference.type
            when :send, :csend, :def then reference.method?(name)
            when :sym then reference.value == name
            when :str then reference.value.scrub.scan(IDENTIFIER_PATTERN).include?(name.to_s)
            else
              # `send(:"format_#{type}")` may call any method starting with `format_`.
              first = reference.children.first
              prefix = first.value.scrub[NAME_PREFIX_PATTERN] if first&.any_str_type?
              prefix.present? && name.start_with?(prefix)
            end
          end
          return if references&.length != 1

          call = references.first
          return unless call.is_a?(RuboCop::AST::SendNode)
          return if call.receiver && !call.self_receiver?
          return unless call.each_ancestor(:class, :module).first.equal?(namespace)
          return if call.each_ancestor(:def).include?(node)

          # A method-level `rescue` or `ensure` needs a `begin` block once inlined, which reads badly in a condition.
          in_condition = [call, *call.each_ancestor].each_cons(2)
                                                    .take_while { |_, parent| !parent.type?(:any_def, :any_block) }
                                                    .any? do |child, parent|
            parent.operator_keyword? || (parent.conditional? && parent.children.first.equal?(child))
          end
          return if in_condition && node.body&.type?(:rescue, :ensure)

          # `Naming/RescuedExceptionsVariableName` stops renaming a rescued variable the caller already uses.
          caller_names = call.each_ancestor(:any_def, :any_block)
                             .to_a
                             .last
                             &.each_descendant(:lvasgn, :argument)
                             &.map(&:name)
          return if caller_names&.intersect?(rescued_variable_names(node).to_a)

          return if !formula_class?(namespace) && !single_use_in_project_index?(namespace, name)
          # Inlining should not push any enclosing method or block over an enabled `Metrics` limit
          # that would then need suppressing.
          return if call.each_ancestor(:any_def, :any_block).any? do |scope|
            if scope.any_block_type?
              next !scope.class_constructor? && inlining_exceeds_length?("Metrics/BlockLength", scope, node)
            end
            next true if inlining_exceeds_length?("Metrics/MethodLength", scope, node)

            max_abc = enabled_metrics_max("Metrics/AbcSize", scope)
            discount_repeated_attributes = !config.for_cop("Metrics/AbcSize")["CountRepeatedAttributes"]
            abc = [scope, node].sum do |method|
              Metrics::Utils::AbcSizeCalculator.calculate(method, discount_repeated_attributes:).first
            end
            next true if max_abc && abc > max_abc

            {
              "Metrics/CyclomaticComplexity" => CyclomaticComplexityScore,
              "Metrics/PerceivedComplexity"  => PerceivedComplexityScore,
            }.any? do |cop_name, score_class|
              max_complexity = enabled_metrics_max(cop_name, scope)
              next false if max_complexity.nil?

              score = score_class.new(config)
              complexity = [scope, node].sum do |method|
                score.reset_repeated_csend
                body = method.body
                body ? score.complexity(body) : 1
              end
              # Each method starts from a score of 1 but the inlined result only has one.
              complexity - 1 > max_complexity
            end
          end

          max_nesting = config.for_enabled_cop("Metrics/BlockNesting")["Max"]
          if max_nesting
            nesting = BlockNestingScore.new(config)
            nests = ->(nested) { nesting.consider_node?(nested) && nesting.count_if_block?(nested) }
            method_nesting = node.each_descendant.select(&nests).map do |nested|
              nested.each_ancestor.take_while { |ancestor| !ancestor.equal?(node) }.count(&nests) + 1
            end.max.to_i
            return if call.each_ancestor.count(&nests) + method_nesting > max_nesting
          end

          add_offense(node.loc.keyword.join(node.loc.name), message: format(MSG, method: name))
        end

        private

        sig {
          params(namespace: T.any(RuboCop::AST::ClassNode, RuboCop::AST::ModuleNode), name: Symbol).returns(T::Boolean)
        }
        def single_use_in_project_index?(namespace, name)
          return false unless project_index

          declaration = resolve_constant_in_index(namespace.identifier)
          return false unless declaration.is_a?(Rubydex::Namespace)

          method = declaration.member("#{name}()")
          return false if !method.is_a?(Rubydex::Method) || method.public?

          definitions, references, symbols = index_name_counts
          definitions[name.to_s] == 1 && references[name.to_s] == 1 && !symbols.include?(name.to_s)
        end

        sig {
          params(cop_name: String, scope: T.any(RuboCop::AST::DefNode, RuboCop::AST::BlockNode),
                 node: RuboCop::AST::DefNode).returns(T::Boolean)
        }
        def inlining_exceeds_length?(cop_name, scope, node)
          max_length = enabled_metrics_max(cop_name, scope)
          return false if max_length.nil?

          cop_config = config.for_cop(cop_name)
          length = [scope, node].sum do |method|
            Metrics::Utils::CodeLengthCalculator.new(
              method, processed_source,
              count_comments: cop_config["CountComments"],
              foldable_types: Array(cop_config["CountAsOne"]).map(&:to_sym)
            ).calculate
          end
          length > max_length
        end

        # The `Max` of an enabled `Metrics` cop, unless it allows the method or block by name.
        sig {
          params(cop_name: String, scope: T.any(RuboCop::AST::DefNode, RuboCop::AST::BlockNode))
            .returns(T.nilable(T.any(Integer, Float)))
        }
        def enabled_metrics_max(cop_name, scope)
          cop_config = config.for_enabled_cop(cop_name)
          name = scope.method_name.to_s
          return if Array(cop_config["AllowedMethods"]).include?(name)
          return if Array(cop_config["AllowedPatterns"]).any? { |pattern| Regexp.new(pattern).match?(name) }

          cop_config["Max"]
        end

        sig { returns([T::Hash[String, Integer], T::Hash[String, Integer], T::Set[String]]) }
        def index_name_counts
          cached = self.class.cached_index_name_counts
          return [cached[1], cached[2], cached[3]] if cached && cached[0].equal?(project_index)

          definitions = project_index.declarations
                                     .grep(Rubydex::Method)
                                     .map { |method| method.unqualified_name.delete_suffix("()") }
                                     .tally
          references = []
          symbols = Set.new
          seen_contents = Set.new
          project_index.documents.each do |document|
            path = URI::RFC2396_PARSER.unescape(document.uri.delete_prefix("file://"))
            source = File.read(path).scrub if File.file?(path)
            # A symlink or copy of a file, e.g. an installed tap, is indexed again and would double its references.
            next if source && !seen_contents.add?(Digest::SHA256.hexdigest(source))

            references.concat(document.method_references.map { |reference| reference.name.delete_suffix("()") })
            # The index has no symbols, e.g. specs stubbing `receive(:name)`, so find them in the source.
            symbols.merge(source.scan(SYMBOL_PATTERN).flatten.compact) if source
          end
          references = references.tally
          self.class.cached_index_name_counts = [project_index, definitions, references, symbols]
          [definitions, references, symbols]
        end
      end
    end
  end
end
