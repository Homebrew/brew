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
        ON_SYSTEM_BLOCK_METHODS = T.let(
          [*RuboCop::Cask::Constants::ON_SYSTEM_METHODS, :on_system].freeze,
          T::Array[Symbol],
        )
        SHA256_KEYS = T.let(
          {
            macos: { arm64: :arm, intel: :intel, x86_64: :intel },
            linux: { arm64: :arm64_linux, intel: :x86_64_linux, x86_64: :x86_64_linux },
          }.freeze,
          T::Hash[Symbol, T::Hash[Symbol, Symbol]],
        )
        OS_SHA256_MESSAGE = "Don't nest `sha256` stanzas in `on_macos` and `on_linux` blocks"

        sig { override.params(cask_block: RuboCop::Cask::AST::CaskBlock).void }
        def on_cask(cask_block)
          @cask_block = T.let(cask_block, T.nilable(RuboCop::Cask::AST::CaskBlock))

          toplevel_stanzas.each do |stanza|
            next unless FLIGHT_STANZA_NAMES.include? stanza.stanza_name

            audit_on_system_blocks(stanza.stanza_node, stanza.stanza_name)
          end

          audit_redundant_nested_on_system_blocks
          audit_arch_conditionals(cask_body, allowed_blocks: FLIGHT_STANZA_NAMES)
          audit_macos_version_conditionals(cask_body, recommend_on_system: false, allowed_blocks: FLIGHT_STANZA_NAMES)
          simplify_sha256_stanzas
          simplify_os_sha256_stanzas
          simplify_arch_version_stanzas
          audit_identical_sha256_across_architectures
        end

        private

        sig { returns(T.nilable(RuboCop::Cask::AST::CaskBlock)) }
        attr_reader :cask_block

        def_delegators :cask_block, :toplevel_stanzas, :cask_body

        sig { void }
        def audit_redundant_nested_on_system_blocks
          cask_body.each_node(:block) do |block_node|
            next unless cask_on_system_conditional_block?(block_node)

            method_node = block_node.method_node
            next unless block_node.each_ancestor(:block).any? do |ancestor|
              cask_on_system_conditional_block?(ancestor) && ancestor.method_node == method_node
            end

            add_offense(method_node, message: "Remove the redundant nested `#{method_node.source}` block.")
          end
        end

        sig { params(node: RuboCop::AST::Node).returns(T::Boolean) }
        def cask_on_system_conditional_block?(node)
          method_node = node.method_node
          return false unless method_node
          return false unless method_node.receiver.nil?
          return false unless ON_SYSTEM_BLOCK_METHODS.include?(method_node.method_name)

          node.each_ancestor.any?(&:cask_block?)
        end

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
        def simplify_os_sha256_stanzas
          return if toplevel_stanzas.any? { |stanza| stanza.stanza_name == :sha256 }

          macos_blocks = toplevel_os_blocks(:on_macos)
          linux_blocks = toplevel_os_blocks(:on_linux)
          return if macos_blocks.count != 1 || linux_blocks.count != 1

          macos_block = macos_blocks.fetch(0)
          linux_block = linux_blocks.fetch(0)

          macos_sha256_nodes = direct_send_nodes(macos_block).select { |node| node.method_name == :sha256 }
          linux_sha256_nodes = direct_send_nodes(linux_block).select { |node| node.method_name == :sha256 }
          return if macos_sha256_nodes.count != 1 || linux_sha256_nodes.count != 1

          macos_sha256 = macos_sha256_nodes.fetch(0)
          linux_sha256 = linux_sha256_nodes.fetch(0)

          version_node = toplevel_stanzas.find { |stanza| stanza.stanza_name == :version }&.stanza_node
          return unless version_node.is_a?(RuboCop::AST::SendNode)

          offending_node(linux_block)
          stanza_sequences = [
            toplevel_stanzas,
            RuboCop::Cask::AST::StanzaBlock.new(macos_block, processed_source.comments).stanzas,
            RuboCop::Cask::AST::StanzaBlock.new(linux_block, processed_source.comments).stanzas,
          ]
          stanzas_need_reordering = stanza_sequences.any? do |stanzas|
            stanzas.each_cons(2).any? do |previous, current|
              previous_index = previous.stanza_index
              current_index = current.stanza_index
              previous_index && current_index && previous_index > current_index
            end
          end
          stanza_grouping_will_edit = [[macos_block, macos_sha256], [linux_block, linux_sha256]].any? do |block, node|
            stanzas = inner_stanzas(block, processed_source.comments)
            stanza_index = stanzas.index { |stanza| stanza.stanza_node == node }
            next false unless stanza_index

            stanza = stanzas.fetch(stanza_index)
            next_stanza = stanzas[stanza_index + 1]
            next false unless next_stanza

            stanza.same_group?(next_stanza) == processed_source[stanza.source_range.last_line].empty?
          end
          comments_would_be_lost = [macos_sha256, linux_sha256].any? do |node|
            processed_source.comments.any? do |comment|
              comment_range = comment.loc.expression
              comment_range.line.between?(node.first_line, node.last_line) ||
                comment_range.last_line == node.first_line - 1
            end
          end
          comments_would_be_lost ||= [[macos_block, macos_sha256], [linux_block, linux_sha256]].any? do |block, node|
            block.block_body == node &&
              (comments_in_node_ranges?(block) ||
                processed_source.comments.any? do |comment|
                  comment_range = comment.loc.expression
                  comment_range.line == block.last_line || comment_range.last_line == block.first_line - 1
                end)
          end
          if stanzas_need_reordering || stanza_grouping_will_edit || comments_would_be_lost
            problem OS_SHA256_MESSAGE
            return
          end

          macos_argument = macos_sha256.first_argument
          linux_argument = linux_sha256.first_argument
          identical_sha256_source = if macos_argument && linux_argument &&
                                       macos_argument.source == linux_argument.source &&
                                       (macos_argument.str_type? ||
                                         (macos_argument.sym_type? && macos_argument.value == :no_check))
            macos_argument.source
          end

          replacement = if identical_sha256_source
            "sha256 #{identical_sha256_source}"
          else
            macos_pairs = sha256_pairs(macos_sha256, macos_block, :macos)
            linux_pairs = sha256_pairs(linux_sha256, linux_block, :linux)
            if macos_pairs.nil? || linux_pairs.nil?
              problem OS_SHA256_MESSAGE
              return
            end

            pairs = (macos_pairs + linux_pairs).sort_by do |key, _value|
              RuboCop::Cask::Constants::SHA256_ARCH_ORDER.index(key) || raise("unexpected sha256 key: #{key}")
            end
            width = pairs.map { |key, _value| key.length }.max.to_i
            prefix = "sha256 "
            continuation = " " * (version_node.source_range.column + prefix.length)
            pairs.each_with_index.map do |(key, value), index|
              key_with_padding = "#{key}:".ljust(width + 2)
              "#{index.zero? ? prefix : continuation}#{key_with_padding}#{value}"
            end.join(",\n")
          end

          problem OS_SHA256_MESSAGE do |corrector|
            corrector.insert_after(range_by_whole_lines(version_node.source_range, include_final_newline: false),
                                   "\n#{" " * version_node.source_range.column}#{replacement}")
            os_blocks_and_sha256 = [[macos_block, macos_sha256], [linux_block, linux_sha256]]
            remove_both_os_blocks = os_blocks_and_sha256.all? { |block, node| block.block_body == node }
            os_blocks_and_sha256.each_with_index do |(block, node), index|
              removal_node = (block.block_body == node) ? block : node
              range = range_by_whole_lines(removal_node.source_range, include_final_newline: true)
              if remove_both_os_blocks && index.zero? &&
                 (preceding_blank_line = processed_source.buffer.source[...range.begin_pos].to_s[/\n[ \t]*\n\z/])
                range = range.adjust(begin_pos: -(preceding_blank_line.length - 1))
              end
              stanzas = inner_stanzas(block, processed_source.comments)
              preserve_following_blank_line = if (stanza_index = stanzas.index do |stanza|
                stanza.stanza_node == node
              end) && stanza_index.positive?
                previous_stanza = stanzas.fetch(stanza_index - 1)
                next_stanza = stanzas[stanza_index + 1]
                next_stanza && !previous_stanza.same_group?(next_stanza)
              end
              following_blank_line = if preserve_following_blank_line
                ""
              else
                processed_source.buffer.source[range.end_pos..].to_s[/\A[ \t]*\n/].to_s
              end
              corrector.remove(range.adjust(end_pos: following_blank_line.length))
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

        sig { params(method: Symbol).returns(T::Array[RuboCop::AST::BlockNode]) }
        def toplevel_os_blocks(method)
          toplevel_stanzas.filter_map do |stanza|
            node = stanza.stanza_node
            node if stanza.stanza_name == method && node.is_a?(RuboCop::AST::BlockNode)
          end
        end

        sig { params(block: RuboCop::AST::BlockNode).returns(T::Array[RuboCop::AST::SendNode]) }
        def direct_send_nodes(block)
          body = block.block_body
          return [] unless body

          (body.begin_type? ? body.child_nodes : [body]).select do |node|
            node.is_a?(RuboCop::AST::SendNode) && node.receiver.nil?
          end
        end

        sig {
          params(
            sha256_node: RuboCop::AST::SendNode,
            block:       RuboCop::AST::BlockNode,
            os:          Symbol,
          ).returns(T.nilable(T::Array[[Symbol, String]]))
        }
        def sha256_pairs(sha256_node, block, os)
          argument = sha256_node.first_argument
          return unless argument

          if argument.hash_type?
            allowed_keys = SHA256_KEYS.fetch(os).values.uniq
            allowed_keys << :x86_64 if os == :macos
            return if argument.pairs.any? do |pair|
              !pair.key.sym_type? || !pair.value.str_type? || !allowed_keys.include?(pair.key.value)
            end

            return argument.pairs.map { |pair| [pair.key.value, pair.value.source] }
          end
          return unless argument.str_type?

          toplevel_depends_on_nodes = toplevel_stanzas.filter_map do |stanza|
            node = stanza.stanza_node
            node if stanza.stanza_name == :depends_on && node.is_a?(RuboCop::AST::SendNode)
          end
          arch_values = (toplevel_depends_on_nodes + direct_send_nodes(block)).filter_map do |node|
            next if node.method_name != :depends_on

            node.arguments.filter_map do |node_argument|
              next unless node_argument.hash_type?

              pair = node_argument.pairs.find { |candidate| candidate.key.sym_type? && candidate.key.value == :arch }
              next unless pair

              if pair.value.sym_type?
                pair.value.value
              elsif pair.value.array_type? && pair.value.values.all?(&:sym_type?)
                pair.value.values.map(&:value)
              else
                false
              end
            end
          end.flatten
          return if arch_values.any? { |value| !value.is_a?(Symbol) }

          keys = if arch_values.empty?
            SHA256_KEYS.fetch(os).values.uniq
          else
            symbol_arch_values = arch_values.grep(Symbol)
            return if symbol_arch_values.any? { |arch| !SHA256_KEYS.fetch(os).key?(arch) }

            symbol_arch_values.filter_map { |arch| SHA256_KEYS.fetch(os)[arch] }.uniq
          end
          keys.map { |key| [key, argument.source] }
        end

        sig { void }
        def audit_identical_sha256_across_architectures
          sha256_stanzas = toplevel_stanzas.select { |stanza| stanza.stanza_name == :sha256 }

          sha256_stanzas.each do |stanza|
            sha256_node = stanza.stanza_node
            next if sha256_node.arguments.count != 1
            next unless sha256_node.arguments.first.hash_type?

            hash_node = sha256_node.arguments.first
            values = hash_node.pairs.filter_map do |pair|
              next unless pair.key.sym_type?
              next unless pair.value.str_type?

              [pair.key.value, pair.value.value]
            end.to_h

            arm_sha = values[:arm]
            intel_sha = values[:intel] || values[:x86_64]

            next unless arm_sha
            next unless intel_sha
            next if arm_sha != intel_sha

            if values.keys.intersect?([:arm64_linux, :x86_64_linux])
              next unless values.values.uniq.one?

              # A scalar also covers omitted Linux architectures, unless dependencies exclude them.
              linux_arches = cask_body.each_node(:send).filter_map do |node|
                next if node.method_name != :depends_on || !node.receiver.nil?
                next unless (argument = node.first_argument)&.hash_type?

                arch_pair = argument.pairs.find { |pair| pair.key.sym_type? && pair.key.value == :arch }
                next unless arch_pair

                scope = node.each_ancestor(:block).take_while { |block| !block.cask_block? }
                next if scope.any? { |block| block.method_name == :on_macos }
                next :unknown unless scope.all? { |block| block.method_name == :on_linux }

                arch_pair.value.sym_type? ? arch_pair.value.value : :unknown
              end
              if linux_arches.empty? || (linux_arches - [:arm64, :intel, :x86_64]).any?
                linux_arches = [:arm64, :intel]
              end
              next unless linux_arches.all? do |arch|
                values.key?((arch == :arm64) ? :arm64_linux : :x86_64_linux)
              end
            end

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
