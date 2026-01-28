# typed: strict
# frozen_string_literal: true

require "keg"

# Helper functions for pinning a formula.
class FormulaPin
  sig { params(formula: Formula).void }
  def initialize(formula)
    @formula = formula
  end

  sig { returns(Pathname) }
  def path
    HOMEBREW_PINNED_KEGS/@formula.name
  end

  sig { params(version: PkgVersion).void }
  def pin_at(version)
    HOMEBREW_PINNED_KEGS.mkpath
    version_path = @formula.rack/version.to_s
    path.make_relative_symlink(version_path) if !pinned? && version_path.exist?
  end

  sig { void }
  def pin
    latest_keg = @formula.installed_kegs.max_by(&:scheme_and_version)
    return if latest_keg.nil?

    pin_at(latest_keg.version)
  end

  sig { void }
  def unpin
    path.unlink if pinned?
    HOMEBREW_PINNED_KEGS.rmdir_if_possible
  end

  sig { returns(T::Boolean) }
  def pinned?
    path.symlink?
  end

  sig { returns(T::Boolean) }
  def pinnable?
    !@formula.installed_prefixes.empty?
  end

  sig { returns(T.nilable(PkgVersion)) }
  def pinned_version
    Keg.new(path.resolved_path).version if pinned?
  end
end
