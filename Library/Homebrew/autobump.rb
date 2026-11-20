# typed: strict
# frozen_string_literal: true

require "autobump_constants"

# Autobump eligibility for formulae and casks.
module Autobump
  autoload :DSL, "autobump/dsl"

  # Recover preset reasons from JSON while preserving custom explanations.
  sig { params(reason: T.any(String, Symbol)).returns(T.any(String, Symbol)) }
  def self.reason_from_api(reason)
    NO_AUTOBUMP_REASONS_LIST.key?(reason.to_sym) ? reason.to_sym : reason
  end
end
