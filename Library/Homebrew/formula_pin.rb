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
    @formula.possible_names.map { |name| HOMEBREW_PINNED_KEGS/name }.find(&:symlink?) ||
      (HOMEBREW_PINNED_KEGS/@formula.name)
  end

  sig { void }
  def pin
    latest_keg = @formula.installed_kegs.max_by(&:scheme_and_version)
    return if latest_keg.nil? || pinned?

    (HOMEBREW_PINNED_KEGS/latest_keg.name).make_relative_symlink(latest_keg.rack/latest_keg.version.to_s)
  end

  sig { void }
  def unpin
    path.unlink if pinned?
    Utils::Path.rmdir_if_possible(HOMEBREW_PINNED_KEGS)
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
    Keg.new(Utils::Path.resolved_path(path)).version if pinned?
  end
end
