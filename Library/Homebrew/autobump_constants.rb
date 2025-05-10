# typed: strict
# frozen_string_literal: true

# TODO: add more reasons here
NO_AUTOBUMP_REASONS_LIST = T.let({
  incompatible_version_format: "incompatible version format",
  bumped_by_upstream:          "bumped by upstream",
  extract_plist:               "livecheck uses `:extract_plist` strategy",
  latest_version:              "`version` is set to `:latest`",
}.freeze, T::Hash[Symbol, String])
