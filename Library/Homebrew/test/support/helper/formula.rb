# typed: strict
# frozen_string_literal: true

require "formulary"

module Test
  module Helper
    module Formula
      extend T::Helpers

      requires_ancestor { RSpec::Mocks::ExampleMethods }

      sig {
        params(
          name: String, path: T.nilable(Pathname), spec: Symbol, alias_path: T.nilable(Pathname),
          tap: T.nilable(Tap), block: T.nilable(T.proc.void)
        ).returns(::Formula)
      }
      def formula(name = "formula_name", path: nil, spec: :stable, alias_path: nil, tap: nil, &block)
        path ||= Formulary.find_formula_in_tap(name, tap || CoreTap.instance)
        Class.new(::Formula, &block).new(name, path, spec, alias_path:, tap:)
      end

      # Use a stubbed {Formulary::FormulaLoader} to make a given formula be found
      # when loading from {Formulary} with `ref`.
      sig { params(formula: ::Formula, ref: T.nilable(T.any(String, Pathname)), call_original: T::Boolean).void }
      def stub_formula_loader(formula, ref = formula.full_name, call_original: false)
        allow(Formulary).to receive(:loader_for).and_call_original if call_original

        loader = instance_double(Formulary::FormulaLoader, get_formula: formula, name: formula.name)
        allow(Formulary).to receive(:loader_for).with(ref, any_args).and_return(loader)
      end
    end
  end
end
