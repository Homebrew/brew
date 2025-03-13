# frozen_string_literal: true

describe Bundle::Remover do
  subject(:remover) { described_class }

  let(:name) { "foo" }

  before { allow(Formulary).to receive(:factory).with(name).and_raise(FormulaUnavailableError) }

  it "raises no errors when requested" do
    expect { remover.possible_names(name, raise_error: false) }.not_to raise_error
  end
end
