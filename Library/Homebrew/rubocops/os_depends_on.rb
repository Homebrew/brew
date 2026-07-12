# typed: strict
# frozen_string_literal: true

require "rubocops/cask/constants/stanza"

module RuboCop
  module Cop
    module Homebrew
      class OSDependsOn < Base
        extend AutoCorrector
        include RangeHelp

        MACOS_ONLY_CASK_STANZAS = [
          :app,
          :audio_unit_plugin,
          :colorpicker,
          :dictionary,
          :input_method,
          :internet_plugin,
          :keyboard_layout,
          :mdimporter,
          :pkg,
          :prefpane,
          :qlplugin,
          :screen_saver,
          :service,
          :suite,
          :vst_plugin,
          :vst3_plugin,
        ].freeze

        CASK_STANZA_ORDER = T.let(RuboCop::Cask::Constants::STANZA_ORDER, T::Array[Symbol])
        MACOS_DEPENDENCY_STANZAS = [:macos, :maximum_macos].freeze

        RESTRICT_ON_SEND = [:depends_on].freeze

        sig { params(node: RuboCop::AST::BlockNode).void }
        def on_block(node)
          send_node = node.children.first
          return unless send_node.is_a?(RuboCop::AST::SendNode)
          return if send_node.method_name != :cask

          add_missing_macos_dependency(node)
        end

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          autocorrect_macos_comparison_strings(node)
          check_redundant_bare_macos(node)
          check_conflicting_os_requirements(node)
        end

        private

        sig { params(node: RuboCop::AST::SendNode).void }
        def autocorrect_macos_comparison_strings(node)
          depends_on_pairs(node).each do |pair|
            key = symbol_key(pair)
            next unless MACOS_DEPENDENCY_STANZAS.include?(key)
            next unless pair.value.str_type?

            match = pair.value.value.match(/\A\s*(?<comparator>>=|<=)\s*:(?<version>\S+)\s*\z/)
            next unless match

            replacement_key = (match[:comparator] == "<=") ? :maximum_macos : :macos
            message = "Use `depends_on #{replacement_key}: :#{match[:version]}`."
            add_offense(pair.value.source_range, message:) do |corrector|
              corrector.replace(pair.source_range, "#{replacement_key}: :#{match[:version]}")
            end
          end
        end

        sig { params(node: RuboCop::AST::SendNode).void }
        def check_redundant_bare_macos(node)
          return unless bare_os_depends_on?(node, :macos)
          return unless sibling_depends_on_pairs(node).any? do |pair|
            MACOS_DEPENDENCY_STANZAS.include?(symbol_key(pair))
          end

          message = "Remove redundant `depends_on :macos`."
          add_offense(node.source_range, message:) do |corrector|
            corrector.remove(range_by_whole_lines(node.source_range, include_final_newline: true))
          end
        end

        sig { params(node: RuboCop::AST::SendNode).void }
        def check_conflicting_os_requirements(node)
          return if !bare_os_depends_on?(node, :linux) && !top_level_macos_depends_on?(node)
          return unless sibling_depends_on_calls(node).any? do |sibling|
            next false if sibling == node

            if bare_os_depends_on?(node, :linux)
              bare_os_depends_on?(sibling, :macos) || top_level_macos_depends_on?(sibling)
            else
              bare_os_depends_on?(sibling, :linux)
            end
          end

          add_offense(node.source_range, message: "`depends_on` cannot be macOS-only and Linux-only.")
        end

        sig { params(node: RuboCop::AST::BlockNode).void }
        def add_missing_macos_dependency(node)
          body = node.body
          return unless body

          stanzas = (body.begin_type? ? body.child_nodes : [body]).filter_map do |child|
            if child.send_type?
              T.cast(child, RuboCop::AST::SendNode)
            elsif child.block_type?
              T.cast(child, RuboCop::AST::BlockNode).send_node
            end
          end
          return if os_depends_on?(body)

          macos_stanza = stanzas.find do |stanza|
            case stanza.method_name
            when :installer
              stanza.arguments.any? do |argument|
                argument.hash_type? && argument.pairs.any? { |pair| symbol_key(pair) == :manual }
              end
            when :os
              pairs = depends_on_pairs(stanza)
              pairs.any? { |pair| symbol_key(pair) == :macos } &&
                pairs.none? { |pair| symbol_key(pair) == :linux }
            when *MACOS_ONLY_CASK_STANZAS
              true
            else
              false
            end
          end
          return unless macos_stanza

          add_offense(macos_stanza.source_range,
                      message: "Add `depends_on :macos` for macOS-only casks.") do |corrector|
            depends_on_stanza_index = CASK_STANZA_ORDER.index(:depends_on) ||
                                      raise("unexpected nil value for depends_on stanza index")
            following_stanza = stanzas.find do |stanza|
              stanza_index = CASK_STANZA_ORDER.index(stanza.method_name)
              stanza_index && stanza_index > depends_on_stanza_index
            end

            if following_stanza
              corrector.insert_before(
                range_by_whole_lines(following_stanza.source_range, include_final_newline: false),
                "  depends_on :macos\n\n",
              )
            elsif (preceding_stanza = stanzas.rfind do |stanza|
              stanza_index = CASK_STANZA_ORDER.index(stanza.method_name)
              stanza_index && stanza_index <= depends_on_stanza_index
            end)
              corrector.insert_after(
                range_by_whole_lines(preceding_stanza.source_range, include_final_newline: true),
                "\n  depends_on :macos\n",
              )
            else
              corrector.insert_before(
                range_by_whole_lines(macos_stanza.source_range, include_final_newline: false),
                "  depends_on :macos\n\n",
              )
            end
          end
        end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Array[RuboCop::AST::PairNode]) }
        def depends_on_pairs(node)
          node.arguments.filter_map do |argument|
            next unless argument.hash_type?

            argument.pairs
          end.flatten
        end

        sig { params(pair: RuboCop::AST::PairNode).returns(T.nilable(Symbol)) }
        def symbol_key(pair)
          key = pair.key
          return unless key.sym_type?

          key.value
        end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Array[RuboCop::AST::PairNode]) }
        def sibling_depends_on_pairs(node)
          sibling_depends_on_calls(node).flat_map { |sibling| depends_on_pairs(sibling) }
        end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Array[RuboCop::AST::SendNode]) }
        def sibling_depends_on_calls(node)
          parent = node.parent
          siblings = parent&.begin_type? ? parent.child_nodes : [node]
          siblings.select { |sibling| sibling.send_type? && sibling.method_name == :depends_on }
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def os_depends_on?(node)
          node.each_node(:send).any? do |send_node|
            send_node = T.cast(send_node, RuboCop::AST::SendNode)
            next false if send_node.method_name != :depends_on

            bare_os_depends_on?(send_node, :macos) || bare_os_depends_on?(send_node, :linux) ||
              top_level_macos_depends_on?(send_node) ||
              depends_on_pairs(send_node).any? { |pair| symbol_key(pair) == :linux }
          end
        end

        sig { params(node: RuboCop::AST::SendNode, os: Symbol).returns(T::Boolean) }
        def bare_os_depends_on?(node, os)
          !!(node.first_argument&.sym_type? && node.first_argument.value == os)
        end

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def top_level_macos_depends_on?(node)
          depends_on_pairs(node).any? { |pair| MACOS_DEPENDENCY_STANZAS.include?(symbol_key(pair)) }
        end
      end
    end
  end
end
