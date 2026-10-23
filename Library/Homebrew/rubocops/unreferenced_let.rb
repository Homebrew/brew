# typed: strict
# frozen_string_literal: true

require "rubocop-rspec"

module RuboCop
  module Cop
    module Homebrew
      # Flags lazy `let` declarations whose name is never referenced. A lazy `let(:name) { ... }`
      # only runs when `name` is called, so an unreferenced one is dead code and is deleted.
      # Eager `let!` is out of scope: it runs for its side effect, so it cannot simply be deleted.
      #
      # Detection is file-scoped and per example group: a reference keeps a `let` alive only in its
      # own, an enclosing or a nested group, not a sibling. References from other files cannot be
      # seen, so the cop prefers false negatives and never flags:
      # - a name also defined by a `subject` in the file;
      # - a `let` inside a `shared_examples` or `shared_context` block;
      # - a `let` in the lineage of an include such as `it_behaves_like` or `include_context`,
      #   unless that shared group is defined in the file or listed in `SharedGroupsReadingNoLets`;
      # - a `let` the `:config` shared context reads by name, such as `cop_config`;
      # - any `let` in a file that dispatches through a name it cannot resolve, e.g. `send("a_#{b}")`.
      #
      # A name counts as referenced if it is called bare, appears as a symbol other than the `let`'s
      # own name argument, or appears as a token inside a string. A `let!` of the same name also
      # counts, but a name inside the `let`'s own block does not.
      #
      # Commonly-named lets such as `let(:formula)` are rarely flagged, so this is not a complete
      # dead-`let` finder.
      #
      # ### Example
      #
      # ```ruby
      # # bad
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
        FRAMEWORK_RESERVED_NAMES = [:cop_config, :other_cops, :cop_options, :gem_versions].freeze
        DYNAMIC_DISPATCH_METHODS = [:send, :public_send, :__send__, :try, :try!, :method, :public_method,
                                    :respond_to?].freeze
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

        sig { params(name: Symbol, block: RuboCop::AST::BlockNode).returns(T::Boolean) }
        def exempt_from_deletion?(name, block)
          FRAMEWORK_RESERVED_NAMES.include?(name) ||
            dynamic_dispatch? ||
            within_shared_definition?(block) ||
            subject_names.include?(name) ||
            includes_in_lineage?(block) ||
            referenced?(name, block)
        end

        # Also removes a preceding `sig`, attached comment lines and a trailing blank line that would
        # be left doubled, unless the line above is a `let` or `subject`.
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
                  # `scan` raises on invalid encoding, e.g. a deliberate bad-UTF-8 test fixture.
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
