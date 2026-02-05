# typed: strict
# frozen_string_literal: true

require "rubocops/shared/helper_functions"

module RuboCop
  module Cop
    # This cop audits `no_autobump!` reason.
    module NoAutobumpHelper
      include HelperFunctions

      PUNCTUATION_MARKS = %w[. ! ?].freeze
      DISALLOWED_NO_AUTOBUMP_REASONS = %w[extract_plist latest_version].freeze

      sig { params(_type: Symbol, reason_node: RuboCop::AST::Node).void }
      def audit_no_autobump(_type, reason_node)
        @offensive_node = T.let(reason_node, T.nilable(RuboCop::AST::Node))

        reason_string = string_content(reason_node)

        if reason_node.sym_type? && DISALLOWED_NO_AUTOBUMP_REASONS.include?(reason_string)
          problem "`:#{reason_string}` reason should not be used"
        end

        return if reason_node.sym_type?

        if reason_string.start_with?("it ")
          problem "Do not start the reason with `it`" do |corrector|
            corrector.replace(T.must(@offensive_node).source_range, "\"#{reason_string[3..]}\"")
          end
        end

        return unless PUNCTUATION_MARKS.include?(reason_string[-1])

        problem "Do not end the reason with a punctuation mark" do |corrector|
          corrector.replace(T.must(@offensive_node).source_range, "\"#{reason_string.chop}\"")
        end
      end
    end
  end
end
