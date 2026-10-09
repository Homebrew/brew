# typed: strict
# frozen_string_literal: true

module Homebrew
  # Provides helper methods for unlinking formulae and kegs with consistent output.
  module Unlink
    sig { params(formula: Formula, locked_formulae: T::Array[Formula], verbose: T::Boolean).void }
    def self.unlink_link_overwrite_formulae(formula, locked_formulae: [], verbose: false)
      overwrite_formulae = formula.link_overwrite_formulae.select(&:linked?)
      overwrite_formulae.select!(&:keg_only?) unless formula.keg_only?

      overwrite_formulae.filter_map(&:any_installed_keg)
                        .select(&:directory?)
                        .each do |keg|
        unlink(keg, verbose:, lock: locked_formulae.none? { |locked_formula| locked_formula.name == keg.name })
      end
    end

    sig { params(keg: Keg, dry_run: T::Boolean, verbose: T::Boolean, lock: T::Boolean).void }
    def self.unlink(keg, dry_run: false, verbose: false, lock: true)
      return keg.lock { unlink(keg, dry_run:, verbose:, lock: false) } if lock

      print "Unlinking #{keg}... "
      puts if verbose
      puts "#{keg.unlink(dry_run:, verbose:)} symlinks removed."
    end
  end
end
