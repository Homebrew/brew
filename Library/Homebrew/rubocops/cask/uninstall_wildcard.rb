# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks for `uninstall`/`zap` wildcards which match too much,
      # e.g. `quit: "*"`, which would target every running application.
      class UninstallWildcard < Base
        # The fewest parts of an ID any cask uses with a wildcard, e.g. the three of
        # `com.example.*`: fewer than this matches too much, as `com.a*` would match
        # every `com.apple.*` ID.
        MINIMUM_ID_PARTS = 3
        MESSAGE = "Include at least %<minimum>d parts of an ID with a wildcard, e.g. `com.example.*`."
        WILDCARD_DIRECTIVES = [:launchctl, :quit, :signal].freeze

        RESTRICT_ON_SEND = [:uninstall, :zap].freeze

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          node.each_descendant(:pair) do |pair|
            next unless pair.key.sym_type?
            next unless WILDCARD_DIRECTIVES.include?(pair.key.value)

            id_values(pair.value).each do |value|
              next unless too_broad_wildcard?(value.source)

              add_offense(value, message: format(MESSAGE, minimum: MINIMUM_ID_PARTS))
            end
          end
        end

        private

        # Segments of an interpolated value can't be judged, so they are skipped.
        sig { params(node: RuboCop::AST::Node).returns(T::Array[RuboCop::AST::Node]) }
        def id_values(node)
          return [node] if node.str_type?

          node.each_descendant(:str).reject { |descendant| descendant.parent&.dstr_type? }
        end

        sig { params(value: String).returns(T::Boolean) }
        def too_broad_wildcard?(value)
          return false unless value.include?("*")

          # The parts also need something to match on, ruling out e.g. `*.*.*`.
          value.split(".").length < MINIMUM_ID_PARTS || !value.match?(/[[:alnum:]]/)
        end
      end
    end
  end
end
