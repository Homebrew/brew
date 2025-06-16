# typed: strict
# frozen_string_literal: true

module Homebrew
  module_function

  sig { returns(String) }
  def no_changes_message
    "No changes to formulae."
  end

  sig { void }
  def migrate_gcc_dependents_if_needed
    return if Settings.read("gcc-rpaths.fixed") == "true"

    Formula.installed.each do |formula|
      next unless formula.tap&.core_tap?

      recursive_runtime_dependencies = Dependency.expand(
        formula,
        cache_key: "update-report",
      ) do |_, dependency|
        Dependency.prune if dependency.build? || dependency.test?
      end
      next unless recursive_runtime_dependencies.map(&:name).include? "gcc"

      keg = formula.installed_kegs.fetch(-1)
      tab = keg.tab
      # Force reinstallation upon `brew upgrade` to fix the bottle RPATH.
      tab.source["versions"]["version_scheme"] = -1
      tab.write
    rescue TapFormulaUnavailableError
      nil
    end

    Settings.write "gcc-rpaths.fixed", true
  end
end
