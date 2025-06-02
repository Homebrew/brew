# typed: strict
# frozen_string_literal: true

module DinrusBrew
  # Provides helper methods for unlinking formulae and kegs with consistent output.
  module Unlink
    sig { params(formula: Formula, verbose: T::Boolean).void }
    def self.unlink_versioned_formulae(formula, verbose: false)
      formula.versioned_formulae
             .select(&:keg_only?)
             .select(&:linked?)
             .filter_map(&:any_installed_keg)
             .select(&:directory?)
             .each do |keg|
        unlink(keg, verbose:)
      end
    end

    sig { params(keg: Keg, dry_run: T::Boolean, verbose: T::Boolean).void }
    def self.unlink(keg, dry_run: false, verbose: false)
      options = { dry_run:, verbose: }

      keg.lock do
        print "Отлинковывается #{keg}... "
        puts if verbose
        puts "#{keg.unlink(**options)} символьных ссылок удалено."
      end
    end
  end
end
