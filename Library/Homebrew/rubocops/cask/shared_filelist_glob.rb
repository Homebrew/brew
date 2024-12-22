# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      class SharedFilelistGlob < Base
        extend AutoCorrector

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return if node.method_name != :zap

          node.each_descendant(:pair).each do |pair|
            symbols = pair.children.select(&:sym_type?).map(&:value)
            next unless symbols.include?(:trash)

            pair.each_descendant(:array).each do |array|
              regex = /\.sfl\d"$/
              message = "Use a glob (*) instead of a specific version (ie. sfl2) for trashing Shared File List paths"

              array.children.each do |item|
                next unless item.source.match?(regex)

                corrected_item = item.source.sub(/sfl\d"$/, "sfl*\"")

                add_offense(item,
                            message:) do |corrector|
                  corrector.replace(item, corrected_item)
                end
              end
            end
          end
        end
      end
    end
  end
end
