# typed: strict
# frozen_string_literal: true

require "version_change"

module Test
  module Helper
    module VersionChange
      # Build a {::VersionChange}: `version_change("name", "1.0", "2.0")` for an upgrade
      # or `version_change("name", "1.0")` for a single version.
      sig {
        params(
          name:        String,
          old_version: String,
          new_version: T.nilable(String),
          size:        T.nilable(String),
        ).returns(::VersionChange)
      }
      def version_change(name, old_version, new_version = nil, size: nil)
        return ::VersionChange.new(name:, new_version: old_version, size:) unless new_version

        ::VersionChange.new(name:, old_version:, new_version:, size:)
      end
    end
  end
end
