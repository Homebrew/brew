# typed: strict
# frozen_string_literal: true

require "forwardable"
require "rubocops/shared/on_system_conditionals_helper"

module RuboCop
  module Cop
    module Cask
      # This cop makes sure that OS conditionals are consistent.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # cask 'foo' do
      #   if MacOS.version == :tahoe
      #     sha256 "..."
      #   end
      # end
      #
      # # good
      # cask 'foo' do
      #   on_tahoe do
      #     sha256 "..."
      #   end
      # end
      # ```
      class OnSystemConditionals < Base
        extend Forwardable
        extend AutoCorrector
        include OnSystemConditionalsHelper
        include CaskHelp

        FLIGHT_STANZA_NAMES = [:preflight, :postflight, :uninstall_preflight, :uninstall_postflight].freeze

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          @cask_block = T.let(cask_block, T.nilable(RuboCop::Cask::AST::CaskBlock))

          toplevel_stanzas.each do |stanza|
            next unless FLIGHT_STANZA_NAMES.include? stanza.stanza_name

            audit_on_system_blocks(stanza.stanza_node, stanza.stanza_name)
          end

          audit_arch_conditionals(cask_body, allowed_blocks: FLIGHT_STANZA_NAMES)
          audit_macos_version_conditionals(cask_body, recommend_on_system: false, allowed_blocks: FLIGHT_STANZA_NAMES)
          simplify_sha256_stanzas
          simplify_arch_version_stanzas
          audit_identical_sha256_across_architectures
        end

        private

        sig { returns(T.nilable(RuboCop::Cask::AST::CaskBlock)) }
        attr_reader :cask_block

        def_delegators :cask_block, :toplevel_stanzas, :cask_body

        sig { void }
        def simplify_sha256_stanzas
          grouped_nodes = Hash.new { |hash, key| hash[key] = {} }

          sha256_on_arch_stanzas(cask_body) do |node, method, value|
            arch = method.to_s.delete_prefix("on_").to_sym
            ast_node = T.cast(node, RuboCop::AST::Node)
            grouped_nodes[ast_node.parent][arch] = { node: ast_node, value: }
          end

          grouped_nodes.each_value do |nodes|
            next if !nodes.key?(:arm) || !nodes.key?(:intel)

            offending_node(nodes[:arm][:node])
            replacement_string = "sha256 arm: #{nodes[:arm][:value].inspect}, intel: #{nodes[:intel][:value].inspect}"
            if comments_in_node_ranges?(nodes[:arm][:node], nodes[:intel][:node])
              problem "Don't nest only the `sha256` stanzas in `on_intel` and `on_arm` blocks"
              next
            end

            problem "Don't nest only the `sha256` stanzas in `on_intel` and `on_arm` blocks" do |corrector|
              corrector.replace(nodes[:arm][:node].source_range, replacement_string)
              corrector.remove(range_by_whole_lines(nodes[:intel][:node].source_range, include_final_newline: true))
            end
          end
        end

        sig { void }
        def simplify_arch_version_stanzas
          grouped_nodes = Hash.new { |hash, key| hash[key] = {} }

          version_and_sha256_on_arch_stanzas(cask_body) do |block_node, arch_method, version_value, sha256_value|
            arch = arch_method.to_s.delete_prefix("on_").to_sym
            ast_block_node = T.cast(block_node, RuboCop::AST::Node)
            grouped_nodes[ast_block_node.parent][arch] = {
              node:          ast_block_node,
              version_value:,
              sha256_value:,
            }
          end

          grouped_nodes.each_value do |nodes|
            next if !nodes.key?(:arm) || !nodes.key?(:intel)

            arm_version = nodes[:arm][:version_value]
            intel_version = nodes[:intel][:version_value]

            next if arm_version != intel_version

            arm_sha = nodes[:arm][:sha256_value]
            intel_sha = nodes[:intel][:sha256_value]
            arm_node = nodes[:arm][:node]
            intel_node = nodes[:intel][:node]

            indent = " " * arm_node.loc.column
            version_str = "version #{arm_version.inspect}"
            sha256_str = if arm_sha == intel_sha
              "sha256 #{arm_sha.inspect}"
            else
              "sha256 arm: #{arm_sha.inspect}, intel: #{intel_sha.inspect}"
            end
            replacement = "#{version_str}\n#{indent}#{sha256_str}"

            offending_node(arm_node)
            if comments_in_node_ranges?(arm_node, intel_node)
              problem "Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks"
              next
            end

            problem "Don't nest identical `version` stanzas in `on_intel` and `on_arm` blocks" do |corrector|
              corrector.replace(arm_node.source_range, replacement)
              corrector.remove(range_by_whole_lines(intel_node.source_range, include_final_newline: true))
            end
          end
        end

        sig { params(nodes: RuboCop::AST::Node).returns(T::Boolean) }
        def comments_in_node_ranges?(*nodes)
          processed_source.comments.any? do |comment|
            comment_range = comment.loc.expression

            nodes.any? do |node|
              node_range = node.source_range
              node_range.begin_pos <= comment_range.begin_pos && comment_range.end_pos <= node_range.end_pos
            end
          end
        end

        sig { void }
        def audit_identical_sha256_across_architectures
          sha256_stanzas = toplevel_stanzas.select { |stanza| stanza.stanza_name == :sha256 }

          sha256_stanzas.each do |stanza|
            sha256_node = stanza.stanza_node
            next if sha256_node.arguments.count != 1
            next unless sha256_node.arguments.first.hash_type?

            hash_node = sha256_node.arguments.first
            arm_sha = T.let(nil, T.nilable(String))
            intel_sha = T.let(nil, T.nilable(String))

            hash_node.pairs.each do |pair|
              key = pair.key
              next unless key.sym_type?

              value = pair.value
              next unless value.str_type?

              case key.value
              when :arm
                arm_sha = value.value
              when :intel
                intel_sha = value.value
              end
            end

            next unless arm_sha
            next unless intel_sha
            next if arm_sha != intel_sha

            offending_node(sha256_node)
            problem "sha256 values for different architectures should not be identical."
          end
        end

        def_node_search :sha256_on_arch_stanzas, <<~PATTERN
          $(block
            (send nil? ${:on_intel :on_arm})
            (args)
            (send nil? :sha256
              (str $_)))
        PATTERN

        def_node_search :version_and_sha256_on_arch_stanzas, <<~PATTERN
          $(block
            (send nil? ${:on_intel :on_arm})
            (args)
            (begin
              (send nil? :version (str $_))
              (send nil? :sha256 (str $_))))
        PATTERN
      end
    end
  end
end
