# typed: strict
# frozen_string_literal: true

# Helper methods for the Homebrew IRB/PRY shell run by `brew irb`

require "formula"
require "formulary"
require "cask/cask_loader"

class String
  # @!visibility private
  sig { params(spec: Symbol).returns(Formula) }
  def f(spec = :stable)
    Formulary.factory(self, spec)
  end

  # @!visibility private
  sig { params(config: T.nilable(T::Hash[Symbol, T.untyped])).returns(Cask::Cask) }
  def c(config: nil)
    Cask::CaskLoader.load(self, config: Cask::Config.new(**config))
  end
end
require "brew_irb_helpers/symbol"
