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
          audit_macos_version_conditionals(cask_body, recommend_on_system: false)
          simplify_sha256_stanzas
          audit_identical_sha256_across_architectures
        end

        private

        sig { returns(T.nilable(RuboCop::Cask::AST::CaskBlock)) }
        attr_reader :cask_block

        def_delegators :cask_block, :toplevel_stanzas, :cask_body

        sig { void }
        def simplify_sha256_stanzas
          nodes = {}

          sha256_on_arch_stanzas(cask_body) do |node, method, value|
            nodes[method.to_s.delete_prefix("on_").to_sym] = { node:, value: }
          end

          return if !nodes.key?(:arm) || !nodes.key?(:intel)

          offending_node(nodes[:arm][:node])
          replacement_string = "sha256 arm: #{nodes[:arm][:value].inspect}, intel: #{nodes[:intel][:value].inspect}"

          problem "Use `#{replacement_string}` instead of nesting the `sha256` stanzas in " \
                  "`on_intel` and `on_arm` blocks" do |corrector|
            corrector.replace(nodes[:arm][:node].source_range, replacement_string)
            corrector.replace(nodes[:intel][:node].source_range, "")
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
      end
    end
  end
end
