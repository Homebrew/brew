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
        LINUX_ONLY_CASK_STANZAS = [:app_image, :package].freeze
        PLATFORM_BLOCKS = [:on_arm, :on_intel, :on_system].freeze

        CASK_STANZA_ORDER = T.let(RuboCop::Cask::Constants::STANZA_ORDER, T::Array[Symbol])
        MACOS_DEPENDENCY_STANZAS = [:macos, :maximum_macos].freeze
        LINUX_DEPENDENCY_STANZAS = [:linux].freeze

        RESTRICT_ON_SEND = [:depends_on].freeze

        sig { params(node: RuboCop::AST::BlockNode).void }
        def on_block(node)
          send_node = node.children.first
          return unless send_node.is_a?(RuboCop::AST::SendNode)
          return if send_node.method_name != :cask

          add_missing_os_dependency(node, :macos)
          add_missing_os_dependency(node, :linux)
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

        sig { params(node: RuboCop::AST::BlockNode, os: Symbol).void }
        def add_missing_os_dependency(node, os)
          body = node.body
          return unless body

          top_level_stanzas = direct_stanzas(body)
          stanzas = top_level_stanzas.flat_map { |stanza| [stanza, *platform_block_stanzas(stanza)] }
          return if os_depends_on?(body)

          os_stanza = stanzas.find { |stanza| os_only_stanza?(stanza, os) }
          return unless os_stanza

          os_name = (os == :macos) ? "macOS" : "Linux"
          if cross_platform_cask?(top_level_stanzas, stanzas, os)
            add_offense(
              os_stanza.source_range,
              message: "Move this #{os_name}-only stanza into an `on_#{os}` block for cross-platform casks.",
            )
            return
          end

          add_offense(os_stanza.source_range,
                      message: "Add `depends_on :#{os}` for #{os_name}-only casks.") do |corrector|
            depends_on_stanza_index = CASK_STANZA_ORDER.index(:depends_on) ||
                                      raise("unexpected nil value for depends_on stanza index")
            following_stanza = top_level_stanzas.find do |stanza|
              stanza_index = CASK_STANZA_ORDER.index(stanza.method_name)
              stanza_index && stanza_index > depends_on_stanza_index
            end

            if following_stanza
              corrector.insert_before(
                range_by_whole_lines(following_stanza.source_range, include_final_newline: false),
                "  depends_on :#{os}\n\n",
              )
            elsif (preceding_stanza = top_level_stanzas.rfind do |stanza|
              stanza_index = CASK_STANZA_ORDER.index(stanza.method_name)
              stanza_index && stanza_index <= depends_on_stanza_index
            end)
              corrector.insert_after(
                range_by_whole_lines(full_stanza_source_range(preceding_stanza), include_final_newline: true),
                "\n  depends_on :#{os}\n",
              )
            else
              corrector.insert_before(
                range_by_whole_lines(os_stanza.source_range, include_final_newline: false),
                "  depends_on :#{os}\n\n",
              )
            end
          end
        end

        sig { params(stanza: RuboCop::AST::SendNode, os: Symbol).returns(T::Boolean) }
        def os_only_stanza?(stanza, os)
          if os == :macos
            return MACOS_ONLY_CASK_STANZAS.include?(stanza.method_name) if stanza.method_name != :installer

            stanza.arguments.any? do |argument|
              argument.hash_type? && argument.pairs.any? { |pair| symbol_key(pair) == :manual }
            end
          else
            LINUX_ONLY_CASK_STANZAS.include?(stanza.method_name)
          end
        end

        sig {
          params(
            top_level_stanzas: T::Array[RuboCop::AST::SendNode],
            stanzas:           T::Array[RuboCop::AST::SendNode],
            os:                Symbol,
          ).returns(T::Boolean)
        }
        def cross_platform_cask?(top_level_stanzas, stanzas, os)
          other_os = (os == :macos) ? :linux : :macos
          other_os_block = (other_os == :macos) ? :on_macos : :on_linux

          # `on_system` always spans both operating systems, so it can never imply a bare OS dependency.
          stanzas.any? { |stanza| stanza.method_name == :on_system } ||
            top_level_stanzas.any? { |stanza| stanza.method_name == other_os_block } ||
            stanzas.any? { |stanza| os_only_stanza?(stanza, other_os) }
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Array[RuboCop::AST::SendNode]) }
        def direct_stanzas(node)
          (node.begin_type? ? node.child_nodes : [node]).filter_map do |child|
            if child.send_type?
              T.cast(child, RuboCop::AST::SendNode)
            elsif child.block_type?
              T.cast(child, RuboCop::AST::BlockNode).send_node
            end
          end
        end

        sig { params(stanza: RuboCop::AST::SendNode).returns(T::Array[RuboCop::AST::SendNode]) }
        def platform_block_stanzas(stanza)
          return [] unless PLATFORM_BLOCKS.include?(stanza.method_name)

          block = stanza.parent
          return [] unless block.is_a?(RuboCop::AST::BlockNode)
          return [] unless (body = block.body)

          nested_stanzas = direct_stanzas(body)
          nested_stanzas + nested_stanzas.flat_map { |nested| platform_block_stanzas(nested) }
        end

        sig { params(stanza: RuboCop::AST::SendNode).returns(Parser::Source::Range) }
        def full_stanza_source_range(stanza)
          parent = stanza.parent
          return parent.source_range if parent.is_a?(RuboCop::AST::BlockNode) && parent.send_node == stanza

          stanza.source_range
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
              top_level_macos_depends_on?(send_node) || top_level_linux_depends_on?(send_node)
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

        sig { params(node: RuboCop::AST::SendNode).returns(T::Boolean) }
        def top_level_linux_depends_on?(node)
          depends_on_pairs(node).any? { |pair| LINUX_DEPENDENCY_STANZAS.include?(symbol_key(pair)) }
        end
      end
    end
  end
end
