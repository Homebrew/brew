# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "keg"

# Helper functions for pinning a formula.
class FormulaPin
  def initialize(formula)
    @formula = formula
  end

  def path
    HOMEBREW_PINNED_KEGS/@formula.name
  end

  def pin_at(version)
    HOMEBREW_PINNED_KEGS.mkpath
    version_path = @formula.rack/version
    path.make_relative_symlink(version_path) if !pinned? && version_path.exist?
  end

  def pin
    latest_keg = @formula.installed_kegs.max_by(&:scheme_and_version)
    return if latest_keg.nil?

    pin_at(latest_keg.version)
  end

  def unpin
    path.unlink if pinned?
    HOMEBREW_PINNED_KEGS.rmdir_if_possible
  end

  def pinned?
    path.symlink?
  end

  def pinnable?
    !@formula.installed_prefixes.empty?
  end

  def pinned_version
    Keg.new(path.resolved_path).version if pinned?
  end
end
