# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-token"

RSpec.describe Homebrew::DevCmd::GenerateCaskToken do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "generate-cask-token"

  it "prints the proposed token for an app name" do
    expect { described_class.new(["Software for Mac.app"]).run }
      .to output(/^Proposed token:\s+software$/).to_stdout
  end

  it "warns without failing for a token containing digits" do
    allow(CoreCaskTap.instance).to receive(:cask_tokens).and_return([])
    expect { described_class.new(["1Password"]).run }.to output(/contains digits/).to_stderr
    expect(Homebrew).not_to be_failed
  end

  it "fails for a token that already exists" do
    allow(CoreCaskTap.instance).to receive(:cask_tokens).and_return(["example"])
    expect { described_class.new(["Example App"]).run }.to output(/already exists/).to_stderr
    expect(Homebrew).to be_failed
  end
end
