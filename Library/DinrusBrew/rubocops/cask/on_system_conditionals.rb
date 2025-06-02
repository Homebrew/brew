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
      #   if MacOS.version == :high_sierra
      #     sha256 "..."
      #   end
      # end
      #
      # # good
      # cask 'foo' do
      #   on_high_sierra do
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
