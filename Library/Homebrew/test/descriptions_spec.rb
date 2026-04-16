# typed: false
# frozen_string_literal: true

require "descriptions"

RSpec.describe Descriptions do
  subject(:descriptions) { described_class.new(descriptions_hash) }

  let(:descriptions_hash) { {} }

  it "can print description for a core Formula" do
    descriptions_hash["homebrew/core/foo"] = "Core foo"
    expect { descriptions.print }.to output("foo: Core foo\n").to_stdout
  end

  it "can print description for an external Formula" do
    descriptions_hash["somedev/external/foo"] = "External foo"
    expect { descriptions.print }.to output("foo: External foo\n").to_stdout
  end

  it "can print descriptions for duplicate Formulae" do
    descriptions_hash["homebrew/core/foo"] = "Core foo"
    descriptions_hash["somedev/external/foo"] = "External foo"

    expect { descriptions.print }.to output(
      <<~EOS,
        homebrew/core/foo: Core foo
        somedev/external/foo: External foo
      EOS
    ).to_stdout
  end

  it "can print descriptions for duplicate core and external Formulae" do
    descriptions_hash["homebrew/core/foo"] = "Core foo"
    descriptions_hash["somedev/external/foo"] = "External foo"
    descriptions_hash["otherdev/external/foo"] = "Other external foo"

    expect { descriptions.print }.to output(
      <<~EOS,
        homebrew/core/foo: Core foo
        otherdev/external/foo: Other external foo
        somedev/external/foo: External foo
      EOS
    ).to_stdout
  end

  it "can print description for a cask" do
    descriptions_hash["homebrew/cask/foo"] = ["Foo", "Cask foo"]
    expect { descriptions.print }.to output("foo: (Foo) Cask foo\n").to_stdout
  end

  it "skips formulae without a description" do
    descriptions_hash["homebrew/core/foo"] = nil

    expect { descriptions.print }.not_to output.to_stdout
  end

  it "skips casks without a description" do
    descriptions_hash["homebrew/cask/foo"] = ["Foo", nil]

    expect { descriptions.print }.not_to output.to_stdout
  end

  it "prints trailing status for interactive formula descriptions" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    descriptions_hash["homebrew/core/foo"] = "Core foo"

    allow(Formula).to receive(:installed).and_return(
      [instance_double(Formula, name: "foo", full_name: "homebrew/core/foo")],
    )
    formula = instance_double(Formula, any_version_installed?: true, deprecated?: false, disabled?: false)
    allow(Formulary).to receive(:factory).with("homebrew/core/foo").and_return(formula)

    expect { descriptions.print }.to output(/foo .*: Core foo/).to_stdout
  end

  it "uses installed and deprecation metadata without loading formulae" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    descriptions_hash["homebrew/core/foo"] = "Core foo"

    descriptions = described_class.new(
      descriptions_hash,
      status_data: { "homebrew/core/foo" => { deprecated: true, disabled: false } },
    )

    allow(Formula).to receive(:installed).and_return(
      [instance_double(Formula, name: "foo", full_name: "homebrew/core/foo")],
    )
    expect(Formulary).not_to receive(:factory)
    expect(Cask::CaskLoader).not_to receive(:load)

    expect { descriptions.print }.to output(/foo .*deprecated.*: Core foo/).to_stdout
  end
end
