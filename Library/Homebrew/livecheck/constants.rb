# typed: strict
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # The {Constants} module provides constants that are intended to be used
    # in `livecheck` block values (e.g. `url`, `regex`).
    module Constants
      # A placeholder string used in resource `livecheck` block URLs that will
      # be replaced with the latest version from the main formula check.
      LATEST_VERSION = "<FORMULA_LATEST_VERSION>"
    end
  end
end
