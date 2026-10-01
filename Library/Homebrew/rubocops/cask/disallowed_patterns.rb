# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks `uninstall`/`zap` for patterns that shouldn't be used.
      class DisallowedPatterns < Base
        DISALLOWED_PATTERNS = T.let([
          {
            pattern: "com.install4j.*",
            reason:  "install4j distributions must include the unique ID number, e.g. " \
                     "`com.install4j.1234-5678-9012-3456`, to prevent matching other applications.",
          },
        ].freeze, T::Array[{ pattern: String, reason: String }])

        RESTRICT_ON_SEND = [:uninstall, :zap].freeze

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          node.each_descendant(:str) do |str|
            DISALLOWED_PATTERNS.each do |disallowed|
              next unless str.source.include?(disallowed.fetch(:pattern))

              add_offense(str, message: disallowed.fetch(:reason))
            end
          end
        end
      end
    end
  end
end
