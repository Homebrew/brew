# typed: strict
# frozen_string_literal: true

require "utils/shell"

module Utils
  module Executable
    module_function

    sig { params(name: String, formula_name: T.nilable(String), reason: String, latest: T::Boolean).returns(Pathname) }
    def ensure!(name, formula_name = nil, reason: "", latest: false)
      formula_name ||= name

      executable = [
        Utils::Shell.which(name),
        Utils::Shell.which(name, ORIGINAL_PATHS),
        HOMEBREW_PREFIX/"opt/#{formula_name}/bin/#{name}",
        HOMEBREW_PREFIX/"bin/#{name}",
      ].compact.find(&:exist?)
      return executable if executable

      Kernel.require "formula"
      T.cast(Formula[formula_name].ensure_installed!(reason:, latest:, executable: name), Pathname)
    end
  end
end
