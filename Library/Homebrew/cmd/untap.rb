# typed: strict
# frozen_string_literal: true

require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def untap_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Remove a tapped formula repository.
      EOS
      switch "-f", "--force",
             description: "Untap even if formulae or casks from this tap are currently installed."

      named_args :tap, min: 1
    end
  end

  sig { void }
  def untap
    args = untap_args.parse

    args.named.to_installed_taps.each do |tap|
      odie "Untapping #{tap} is not allowed" if tap.core_tap? && Homebrew::EnvConfig.no_install_from_api?

      if Homebrew::EnvConfig.no_install_from_api? || (!tap.core_tap? && !tap.core_cask_tap?)
        installed_formula_names = T.let(nil, T.nilable(T::Set[String]))
        installed_tap_formulae = tap.formula_names.map do |formula_name|
          # initialise lazily in case there's no formulae in this tap
          installed_formula_names ||= Set.new(Formula.installed_formula_names)
          next unless installed_formula_names.include?(formula_name)

          formula = begin
            Formulary.factory("#{tap.name}/#{formula_name}")
          rescue
            # Don't blow up because of a single unavailable formula.
            next
          end

          # Can't use Formula#any_version_installed? because it doesn't consider
          # taps correctly.
          formula if formula.installed_kegs.any? { |keg| keg.tab.tap == tap }
        end.compact

        installed_cask_tokens = T.let(nil, T.nilable(T::Set[String]))
        installed_tap_casks = tap.cask_tokens.map do |cask_token|
          # initialise lazily in case there's no casks in this tap
          installed_cask_tokens ||= Set.new(Cask::Caskroom.tokens)
          next unless installed_cask_tokens.include?(cask_token)

          cask = begin
            Cask::CaskLoader.load("#{tap.name}/#{cask_token}")
          rescue
            # Don't blow up because of a single unavailable cask.
            next
          end

          cask if cask.installed?
        end.compact

        if installed_tap_formulae.present? || installed_tap_casks.present?
          installed_names = (installed_tap_formulae + installed_tap_casks.map(&:token)).join("\n")
          if args.force? || Homebrew::EnvConfig.developer?
            opoo <<~EOS
              Untapping #{tap} even though it contains the following installed formulae or casks:
              #{installed_names}
            EOS
          else
            odie <<~EOS
              Refusing to untap #{tap} because it contains the following installed formulae or casks:
              #{installed_names}
            EOS
          end
        end
      end

      tap.uninstall manual: true
    end
  end
end
