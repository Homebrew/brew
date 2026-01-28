# typed: strict
# frozen_string_literal: true

# This file should be the first `require` in all entrypoints outside the `brew` environment.

require_relative "standalone/init"
require_relative "standalone/sorbet"
