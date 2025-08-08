# typed: strict
# frozen_string_literal: true

require "pkg_version"

module Homebrew
  # A stub for a formula, with only the information needed to fetch the bottle manifest.
  class FormulaStub < T::Struct
    const :name, String
    const :pkg_version, PkgVersion
    # TODO: actually implement version_scheme
    const :version_scheme, Integer, default: 0
    const :rebuild, Integer, default: 0
    const :sha256, T.nilable(String)

    sig { returns(Version) }
    def version
      pkg_version.version
    end

    sig { returns(Integer) }
    def revision
      pkg_version.revision
    end
  end
end
