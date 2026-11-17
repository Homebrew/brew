# typed: true
# frozen_string_literal: true

require "formula_pin"

RSpec.describe FormulaPin do
  subject(:formula_pin) { described_class.new(formula) }

  let(:name) { "double" }
  let(:formula) { instance_double(Formula, name:, rack: HOMEBREW_CELLAR/name, possible_names: [name]) }

  before do
    formula.rack.mkpath

    allow(formula).to receive(:installed_prefixes) do
      formula.rack.directory? ? formula.rack.subdirs.sort : []
    end

    allow(formula).to receive(:installed_kegs) do
      formula.installed_prefixes.map { |prefix| Keg.new(prefix) }
    end
  end

  it "is not pinnable by default" do
    expect(formula_pin).not_to be_pinnable
  end

  it "is pinnable if the Keg exists" do
    (formula.rack/"0.1").mkpath
    expect(formula_pin).to be_pinnable
  end

  specify "#pin and #unpin" do
    (formula.rack/"0.1").mkpath

    formula_pin.pin
    expect(formula_pin).to be_pinned
    expect(HOMEBREW_PINNED_KEGS/name).to be_a_directory
    expect(HOMEBREW_PINNED_KEGS.children.count).to eq(1)

    formula_pin.unpin
    expect(formula_pin).not_to be_pinned
    expect(HOMEBREW_PINNED_KEGS).not_to be_a_directory
  end

  context "when the Keg is in the Rack of an alias" do
    let(:alias_name) { "double-alias" }
    let(:alias_keg) { HOMEBREW_CELLAR/alias_name/"0.1" }

    before do
      alias_keg.mkpath
      allow(formula).to receive_messages(possible_names: [name, alias_name], installed_kegs: [Keg.new(alias_keg)])
    end

    it "pins the Keg" do
      formula_pin.pin

      expect(formula_pin.pinned_version).to eq(PkgVersion.parse("0.1"))
    end

    it "finds a pin recorded under the alias" do
      HOMEBREW_PINNED_KEGS.mkpath
      (HOMEBREW_PINNED_KEGS/alias_name).make_relative_symlink(alias_keg)

      expect(formula_pin).to be_pinned
    end
  end
end
