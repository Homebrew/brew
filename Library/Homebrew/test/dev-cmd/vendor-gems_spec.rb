# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/vendor-gems"

RSpec.describe Homebrew::DevCmd::VendorGems do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "vendor-gems"

  sig { returns(Homebrew::DevCmd::VendorGems) }
  def vendor_gems_command
    described_class.new(["--no-commit"]).tap do |command|
      allow(command).to receive(:run_bundle)
      allow(command).to receive(:ohai)
      allow(Utils::GemSetup).to receive(:setup_gem_environment!)
      allow(Utils::GemSetup).to receive(:valid_gem_groups).and_return([])
    end
  end

  it "rejects a stale Bootsnap core gem list" do
    command = vendor_gems_command
    allow(Homebrew::Bootsnap).to receive(:core_gem_names).and_return([])

    expect { command.run }.to raise_error(RuntimeError, /Bootsnap core gem list is out of date/)
  end

  it "accepts reordered Bootsnap core gems" do
    command = vendor_gems_command
    core_gem_names = Homebrew::Bootsnap.core_gem_names.reverse
    allow(Homebrew::Bootsnap).to receive(:core_gem_names).and_return(core_gem_names)

    expect { command.run }.not_to raise_error
  end
end
