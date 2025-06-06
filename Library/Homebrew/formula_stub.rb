# typed: strict
# frozen_string_literal: true

require "pkg_version"

module Homebrew
  # A stub for a formula, with only the information needed to fetch the bottle manifest.
  class FormulaStub < T::Struct
    const :name, String
    const :pkg_version, PkgVersion
    const :rebuild, Integer
    const :sha256, T.nilable(String)

    sig { params(name: String, array: [String, Integer, T.nilable(String)]).returns(FormulaStub) }
    def self.from_array(name, array)
      new(
        name:        name,
        pkg_version: PkgVersion.parse(array[0]),
        rebuild:     array[1],
        sha256:      array[2],
      )
    end
  end
end
