# frozen_string_literal: true

require "formulary"

module Test
  module Helper
    module Formula
      def formula(name = "formula_name", path: Formulary.core_path(name), spec: :stable, alias_path: nil, tap: nil,
                  &block)
        Class.new(::Formula, &block).new(name, path, spec, alias_path:, tap:)
      end

      # Use a stubbed {Formulary::FormulaLoader} to make a given formula be found
      # when loading from {Formulary} with `ref`.
      def stub_formula_loader(formula, ref = formula.full_name, call_original: false)
        allow(Formulary).to receive(:loader_for).and_call_original if call_original

        loader = instance_double(Formulary::FormulaLoader, get_formula: formula)
        allow(Formulary).to receive(:loader_for).with(ref, any_args).and_return(loader)
      end
    end
  end
end
