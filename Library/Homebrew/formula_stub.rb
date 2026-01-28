# typed: strict
# frozen_string_literal: true

require "pkg_version"

module Homebrew
  # A stub for a formula, with only the information needed to fetch the bottle manifest.
  class FormulaStub < T::Struct
    const :name, String
    const :pkg_version, PkgVersion
    const :version_scheme, Integer, default: 0
    const :rebuild, Integer, default: 0
    const :sha256, T.nilable(String)
    const :aliases, T::Array[String], default: []
    const :oldnames, T::Array[String], default: []

    sig { returns(Version) }
    def version
      pkg_version.version
    end

    sig { returns(Integer) }
    def revision
      pkg_version.revision
    end

    sig { params(other: T.anything).returns(T::Boolean) }
    def ==(other)
      case other
      when FormulaStub
        name == other.name &&
          pkg_version == other.pkg_version &&
          version_scheme == other.version_scheme &&
          rebuild == other.rebuild &&
          sha256 == other.sha256 &&
          aliases == other.aliases &&
          oldnames == other.oldnames
      else
        false
      end
    end
  end
end
