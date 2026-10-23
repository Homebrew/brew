# typed: strict
# frozen_string_literal: true

require "rubocop-rspec"

module RuboCop
  module Cop
    module Homebrew
      # Flags lazy `let` declarations whose name is never referenced. A lazy `let(:name) { ... }`
      # is only evaluated when `name` is called, so an unreferenced one is dead code -- its block
      # never runs -- and is deleted.
      #
      # Eager `let!` is intentionally out of scope: it runs its block before every example for its
      # side effect even when unreferenced, so it cannot simply be deleted. Only plain `let` is
      # handled here.
      #
      # Detection is file-scoped and per example group: a reference keeps a `let` alive only in its
      # own, an enclosing or a nested group, not a sibling. A `let` referenced only from another
      # file (through a shared example or an included test harness) cannot be seen, so the cop
      # stays conservative and prefers false negatives over false positives:
      # - a name also defined by a `subject` in the file (a `super` chain) is never flagged;
      # - a `let` declared lexically inside a `shared_examples` / `shared_examples_for` /
      #   `shared_context` block is skipped (its consumers live in other files);
      # - every `let` in the lineage of an `it_behaves_like` / `it_should_behave_like` /
      #   `include_examples` / `include_context` is skipped, because an included shared block may
      #   reference the binding by a name we cannot follow statically, unless that shared group is
      #   defined in the file or listed in `SharedGroupsReadingNoLets`;
      # - `let(:cop_config)` is skipped: it is a rubocop-rspec contract consumed by the `:config`
      #   shared context, not by a reference in the spec file; and
      # - every `let` in a file that reflectively dispatches through a name we cannot resolve
      #   statically (e.g. `send("expected_#{type}")`) is skipped, since any `let` could be the
      #   target.
      # A name counts as referenced if it is called bare (`foo`), appears as a symbol (`:foo`)
      # anywhere but the let's own name argument, or appears as an identifier-shaped token inside
      # any string/heredoc literal -- covering dynamic dispatch, `:foo` entries in data tables the
      # spec later dispatches on, and bindings named only inside raw SQL/GraphQL text. A `let!`
      # counts as reading its own name, and a name inside the let's own block does not keep it.
      #
      # Because a bare `:foo` symbol anywhere counts as a reference, commonly-named lets
      # (`let(:formula)`, `let(:cask)`, `let(:id)`) are essentially never flagged. This conservative
      # bias means the cop realistically only deletes distinctively-named dead lets; it is not a
      # complete dead-`let` finder.
      #
      # ### Example
      #
      # ```ruby
      # # bad (name never referenced -- deleted, the block never runs)
      # let(:unused) { create(:thing) }
      #
      # # good
      # let(:thing) { create(:thing) }
      # it { expect(thing).to be_present }
      # ```
      class UnreferencedLet < ::RuboCop::Cop::RSpec::Base
        extend AutoCorrector
        include RangeHelp

        LAZY_DEFINITION_METHODS = [:let, :subject].freeze
        # `let`s consumed by a test framework rather than by a reference in the spec file. RuboCop's
        # own `:config` shared context (used by every cop spec) reads `cop_config`, `other_cops`,
        # `cop_options` and `gem_versions` by name from inside the framework, so they are live even
        # though the spec never names them.
        FRAMEWORK_RESERVED_NAMES = [:cop_config, :other_cops, :cop_options, :gem_versions].freeze
        # Reflective dispatch methods whose target is the first argument. When that argument is not
        # a statically-resolvable name (a `sym` or plain `str`) -- e.g. `send("expected_#{type}")` --
        # the called name cannot be known, so the whole file is left untouched.
        DYNAMIC_DISPATCH_METHODS = [:send, :public_send, :__send__, :try, :try!, :method, :public_method,
                                    :respond_to?].freeze
        # Identifier-shaped tokens inside a string/heredoc literal. A `let` whose name appears only
        # inside string text -- e.g. a binding or column referenced in raw SQL/GraphQL the spec
        # later executes -- counts as referenced, so it is not deleted.
        IDENTIFIER_IN_STRING = /[A-Za-z_]\w*[!?]?/
        MSG = "Remove unreferenced `let(:%<name>s)` -- its name is never used, so the block never runs."
        RESTRICT_ON_SEND = [:let].freeze

        # @!method subject_name(node)
        def_node_matcher :subject_name, <<~PATTERN
          (any_block (send nil? :subject (sym $_) ...) ...)
        PATTERN

        # @!method shared_group_name(node)
        def_node_matcher :shared_group_name, <<~PATTERN
          (any_block (send #rspec? #SharedGroups.all ({str sym} $_) ...) ...)
        PATTERN

        # Autocorrect re-inspects with the same cop instance, so drop the nodes of the previous parse.
        sig { void }
        def on_new_investigation
          super

          @dynamic_dispatch = @references = @subject_names = @unresolved_includes = nil
        end

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return unless node.receiver.nil?

          name_argument = node.first_argument
          return unless name_argument&.sym_type?

          block = node.block_node
          return unless block

          name = name_argument.value
          return if exempt_from_deletion?(name, block)

          add_offense(node.loc.selector, message: format(MSG, name:)) do |corrector|
            corrector.remove(removal_range(block))
          end
        end

        private

        # A lazy `let` is exempt from deletion whenever file-scoped analysis cannot prove its name
        # is dead: its name is a framework-reserved contract (e.g. `cop_config`), the file
        # dispatches through a name we cannot resolve statically, an include in its lineage may read
        # it, the `let` is lexically inside a shared-example definition, a `subject` of the same
        # name may override it, or it is referenced in its lineage.
        sig { params(name: Symbol, block: RuboCop::AST::BlockNode).returns(T::Boolean) }
        def exempt_from_deletion?(name, block)
          FRAMEWORK_RESERVED_NAMES.include?(name) ||
            dynamic_dispatch? ||
            within_shared_definition?(block) ||
            subject_names.include?(name) ||
            includes_in_lineage?(block) ||
            referenced?(name, block)
        end

        # Delete the `let` block, plus:
        # - an immediately-preceding `sig { ... }` (so a Sorbet signature is not left dangling),
        # - explanatory comment lines attached directly above it (so they are not orphaned), and
        # - a single trailing blank line where removal would otherwise leave a stray/duplicate
        #   blank -- unless the line above is a `let`/`subject`, where that blank is the required
        #   separator after the now-final let and must stay.
        sig { params(node: RuboCop::AST::BlockNode).returns(Parser::Source::Range) }
        def removal_range(node)
          lines = processed_source.lines
          start_line = node.source_range.first_line
          end_line = node.source_range.last_line

          sig = preceding_sig(node)
          start_line = sig.source_range.first_line if sig

          start_line -= 1 while start_line > 1 && absorbable_comment?(lines[start_line - 2])

          if end_line < lines.size && blank_line?(lines[end_line]) &&
             !(start_line > 1 && let_or_subject_line?(lines[start_line - 2]))
            end_line += 1
          end

          buffer = processed_source.buffer
          range_by_whole_lines(
            buffer.line_range(start_line).join(buffer.line_range(end_line)),
            include_final_newline: true,
          )
        end

        sig { params(source_line: T.nilable(String)).returns(T::Boolean) }
        def absorbable_comment?(source_line)
          return false if source_line.nil?

          stripped = source_line.strip
          stripped.start_with?("#") && !stripped.start_with?("# rubocop:")
        end

        sig { params(source_line: T.nilable(String)).returns(T::Boolean) }
        def blank_line?(source_line)
          return false if source_line.nil?

          source_line.strip.empty?
        end

        sig { params(source_line: T.nilable(String)).returns(T::Boolean) }
        def let_or_subject_line?(source_line)
          return false if source_line.nil?

          source_line.match?(/\A\s*(?:let!?|subject)\b/)
        end

        sig { params(node: RuboCop::AST::BlockNode).returns(T.nilable(RuboCop::AST::BlockNode)) }
        def preceding_sig(node)
          sibling = node.left_sibling
          return unless sibling.is_a?(::RuboCop::AST::BlockNode)
          return unless sibling.method?(:sig)

          sibling
        end

        sig { params(node: RuboCop::AST::BlockNode).returns(T::Boolean) }
        def within_shared_definition?(node)
          node.each_ancestor(:any_block).any? { |ancestor| shared_group?(ancestor) }
        end

        # `nil` is file-wide: outside any group, or inside a shared group, which runs wherever included.
        sig { params(node: RuboCop::AST::Node).returns(T.nilable(RuboCop::AST::Node)) }
        def example_group_of(node)
          ancestors = node.each_ancestor(:any_block).to_a
          return if ancestors.any? { |ancestor| shared_group?(ancestor) }

          ancestors.find { |ancestor| example_group?(ancestor) }
        end

        sig { params(group: T.nilable(RuboCop::AST::Node), other: T.nilable(RuboCop::AST::Node)).returns(T::Boolean) }
        def same_lineage?(group, other)
          return true if group.nil? || other.nil? || group.equal?(other)

          group.each_ancestor.any? { |ancestor| ancestor.equal?(other) } ||
            other.each_ancestor.any? { |ancestor| ancestor.equal?(group) }
        end

        sig { params(block: RuboCop::AST::BlockNode).returns(T::Boolean) }
        def includes_in_lineage?(block)
          group = example_group_of(block)
          unresolved_includes.any? { |include_call| same_lineage?(example_group_of(include_call), group) }
        end

        sig { returns(T::Array[RuboCop::AST::Node]) }
        def unresolved_includes
          @unresolved_includes ||= T.let(
            begin
              ast = processed_source.ast
              readless_groups = Set.new(cop_config.fetch("SharedGroupsReadingNoLets", []))
              ast&.each_node(:any_block) do |node|
                group_name = shared_group_name(node)
                readless_groups << group_name.to_s if group_name
              end
              include_calls = ast&.each_node(:call)&.select { |node| include?(node) } || []
              include_calls.reject do |node|
                group = node.first_argument
                group&.type?(:str, :sym) && readless_groups.include?(group.value.to_s)
              end
            end,
            T.nilable(T::Array[RuboCop::AST::Node]),
          )
        end

        sig { returns(T::Set[Symbol]) }
        def subject_names
          @subject_names ||= T.let(
            Set.new(processed_source.ast&.each_node(:any_block)&.filter_map { |node| subject_name(node) }),
            T.nilable(T::Set[Symbol]),
          )
        end

        # True when the file reflectively dispatches through a name we cannot resolve statically --
        # `send`/`public_send`/`method`/etc. called with anything other than a `sym` or plain `str`
        # first argument (most commonly an interpolated string, `send("expected_#{type}")`). In
        # that case any `let` in the file could be the dispatch target, so none are deleted.
        sig { returns(T::Boolean) }
        def dynamic_dispatch?
          @dynamic_dispatch = T.let(@dynamic_dispatch, T.nilable(T::Boolean))
          return @dynamic_dispatch unless @dynamic_dispatch.nil?

          ast = processed_source.ast
          @dynamic_dispatch = !ast.nil? && ast.each_node(:call).any? do |send_node|
            next false unless DYNAMIC_DISPATCH_METHODS.include?(send_node.method_name)

            target = send_node.first_argument
            !target.nil? && !target.sym_type? && !target.str_type?
          end
        end

        sig { params(name: Symbol, block: RuboCop::AST::BlockNode).returns(T::Boolean) }
        def referenced?(name, block)
          group = example_group_of(block)
          references.fetch(name, []).any? do |reference|
            reference.each_ancestor.none? { |ancestor| ancestor.equal?(block) } &&
              same_lineage?(example_group_of(reference), group)
          end
        end

        # A name is "referenced" if it is called as a bare method (`foo`), appears as a symbol
        # literal (`:foo`) other than the let/subject's own name argument, or appears as an
        # identifier-shaped token inside any string/heredoc literal. The symbol and string cases
        # cover indirect invocation -- `send(:foo)` / `send("foo")`, a `:foo`/`"foo"` listed in a
        # data table the spec later dispatches on, or a binding named only inside raw SQL/GraphQL
        # text the spec executes -- which file-scoped analysis cannot otherwise follow. (Tokenizing
        # string bodies, rather than matching the whole string, keeps a `let` referenced only from
        # inside a multi-word heredoc from being deleted.) Interpolated-string *dispatch* is handled
        # separately by `dynamic_dispatch?`, which exempts the whole file.
        sig { returns(T::Hash[Symbol, T::Array[RuboCop::AST::Node]]) }
        def references
          @references ||= T.let(
            begin
              ast = processed_source.ast
              references = Hash.new { |hash, name| hash[name] = [] }
              ast&.each_node(:sym, :str, :call) do |node|
                if node.sym_type?
                  references[node.value] << node unless lazy_definition_argument?(node)
                elsif node.str_type?
                  # A string with invalid encoding (e.g. a deliberate bad-UTF-8 test fixture) cannot
                  # contain an identifier-shaped reference and would raise on `scan`, so skip it.
                  if node.value.valid_encoding?
                    node.value.scan(IDENTIFIER_IN_STRING) do |token|
                      references[token.to_sym] << node
                    end
                  end
                elsif node.receiver.nil? && node.arguments.empty?
                  references[node.method_name] << node
                end
              end
              references
            end,
            T.nilable(T::Hash[Symbol, T::Array[RuboCop::AST::Node]]),
          )
        end

        sig { params(sym_node: RuboCop::AST::Node).returns(T::Boolean) }
        def lazy_definition_argument?(sym_node)
          parent = sym_node.parent
          return false if parent.nil? || !parent.send_type? || !parent.receiver.nil?

          LAZY_DEFINITION_METHODS.include?(parent.method_name)
        end
      end
    end
  end
end
