# typed: strict
# frozen_string_literal: true

require "formula_installer"
require "cask/installer"

module Homebrew
  module Install
    # Installers retained after the combined formula and cask download phase.
    class FetchResult < T::Struct
      const :formula_installers, T::Array[FormulaInstaller]
      const :dependent_formula_installers, T::Array[FormulaInstaller]
      const :cask_installers, T::Array[Cask::Installer]
    end
  end
end
