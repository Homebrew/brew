# frozen_string_literal: true

require "descriptions"

describe Descriptions do
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
end
