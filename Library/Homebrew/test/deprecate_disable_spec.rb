# frozen_string_literal: true

require "deprecate_disable"

RSpec.describe DeprecateDisable do
  let(:deprecate_date) { Date.parse("2020-01-01") }
  let(:disable_date) { deprecate_date >> DeprecateDisable::REMOVE_DISABLED_TIME_WINDOW }
  let(:deprecated_formula) do
    instance_double(Formula, deprecated?: true, disabled?: false, deprecation_reason: :does_not_build,
                    deprecation_replacement: nil, deprecation_date: nil, disable_date: nil)
  end
  let(:deprecated_formula_with_date) do
    instance_double(Formula, deprecated?: true, disabled?: false, deprecation_reason: :does_not_build,
                    deprecation_replacement: nil, deprecation_date: deprecate_date, disable_date: nil)
  end
  let(:disabled_formula) do
    instance_double(Formula, deprecated?: false, disabled?: true, disable_reason: "is broken",
                    disable_replacement: nil, deprecation_date: nil, disable_date: nil)
  end
  let(:disabled_formula_with_date) do
    instance_double(Formula, deprecated?: false, disabled?: true, disable_reason: :does_not_build,
                    disable_replacement: nil, deprecation_date: nil, disable_date: disable_date)
  end
  let(:deprecated_cask) do
    instance_double(Cask::Cask, deprecated?: true, disabled?: false, deprecation_reason: :discontinued,
                   deprecation_replacement: nil, deprecation_date: nil, disable_date: nil)
  end
  let(:disabled_cask) do
    instance_double(Cask::Cask, deprecated?: false, disabled?: true, disable_reason: nil,
                    disable_replacement: nil, deprecation_date: nil, disable_date: nil)
  end
  let(:deprecated_formula_with_replacement) do
    instance_double(Formula, deprecated?: true, disabled?: false, deprecation_reason: :does_not_build,
                    deprecation_replacement: "foo", deprecation_date: nil, disable_date: nil)
  end
  let(:disabled_formula_with_replacement) do
    instance_double(Formula, deprecated?: false, disabled?: true, disable_reason: "is broken",
                    disable_replacement: "bar", deprecation_date: nil, disable_date: nil)
  end
  let(:deprecated_cask_with_replacement) do
    instance_double(Cask::Cask, deprecated?: true, disabled?: false, deprecation_reason: :discontinued,
                    deprecation_replacement: "baz", deprecation_date: nil, disable_date: nil)
  end
  let(:disabled_cask_with_replacement) do
    instance_double(Cask::Cask, deprecated?: false, disabled?: true, disable_reason: nil,
                    disable_replacement: "qux", deprecation_date: nil, disable_date: nil)
  end

  before do
    formulae = [
      deprecated_formula,
      deprecated_formula_with_date,
      disabled_formula,
      disabled_formula_with_date,
      deprecated_formula_with_replacement,
      disabled_formula_with_replacement,
    ]

    casks = [
      deprecated_cask,
      disabled_cask,
      deprecated_cask_with_replacement,
      disabled_cask_with_replacement,
    ]

    formulae.each do |f|
      allow(f).to receive(:is_a?).with(Formula).and_return(true)
      allow(f).to receive(:is_a?).with(Cask::Cask).and_return(false)
    end

    casks.each do |c|
      allow(c).to receive(:is_a?).with(Formula).and_return(false)
      allow(c).to receive(:is_a?).with(Cask::Cask).and_return(true)
    end
  end

  describe "::type" do
    it "returns :deprecated if the formula is deprecated" do
      expect(described_class.type(deprecated_formula)).to eq :deprecated
    end

    it "returns :disabled if the formula is disabled" do
      expect(described_class.type(disabled_formula)).to eq :disabled
    end

    it "returns :deprecated if the cask is deprecated" do
      expect(described_class.type(deprecated_cask)).to eq :deprecated
    end

    it "returns :disabled if the cask is disabled" do
      expect(described_class.type(disabled_cask)).to eq :disabled
    end
  end

  describe "::message" do
    it "returns a deprecation message with a preset formula reason" do
      expect(described_class.message(deprecated_formula))
        .to eq "deprecated because it does not build!"
    end

    it "returns a deprecation message with disable date" do
      allow(Date).to receive(:today).and_return(deprecate_date + 1)
      expect(described_class.message(deprecated_formula_with_date))
        .to eq "deprecated because it does not build! It will be disabled on #{disable_date}."
    end

    it "returns a disable message with a custom reason" do
      expect(described_class.message(disabled_formula))
        .to eq "disabled because it is broken!"
    end

    it "returns a disable message with disable date" do
      expect(described_class.message(disabled_formula_with_date))
        .to eq "disabled because it does not build! It was disabled on #{disable_date}."
    end

    it "returns a deprecation message with a preset cask reason" do
      expect(described_class.message(deprecated_cask))
        .to eq "deprecated because it is discontinued upstream!"
    end

    it "returns a deprecation message with no reason" do
      expect(described_class.message(disabled_cask))
        .to eq "disabled!"
    end

    it "returns a replacement message for a deprecated formula" do
      expect(described_class.message(deprecated_formula_with_replacement))
        .to eq "deprecated because it does not build!\nReplacement:\n  brew install foo\n"
    end

    it "returns a replacement message for a disabled formula" do
      expect(described_class.message(disabled_formula_with_replacement))
        .to eq "disabled because it is broken!\nReplacement:\n  brew install bar\n"
    end

    it "returns a replacement message for a deprecated cask" do
      expect(described_class.message(deprecated_cask_with_replacement))
        .to eq "deprecated because it is discontinued upstream!\nReplacement:\n  brew install baz\n"
    end

    it "returns a replacement message for a disabled cask" do
      expect(described_class.message(disabled_cask_with_replacement))
        .to eq "disabled!\nReplacement:\n  brew install qux\n"
    end
  end

  describe "::to_reason_string_or_symbol" do
    it "returns the original string if it isn't a formula preset reason" do
      expect(described_class.to_reason_string_or_symbol("discontinued", type: :formula)).to eq "discontinued"
    end

    it "returns the original string if it isn't a cask preset reason" do
      expect(described_class.to_reason_string_or_symbol("does_not_build", type: :cask)).to eq "does_not_build"
    end

    it "returns a symbol if the original string is a formula preset reason" do
      expect(described_class.to_reason_string_or_symbol("does_not_build", type: :formula))
        .to eq :does_not_build
    end

    it "returns a symbol if the original string is a cask preset reason" do
      expect(described_class.to_reason_string_or_symbol("discontinued", type: :cask))
        .to eq :discontinued
    end
  end
end
