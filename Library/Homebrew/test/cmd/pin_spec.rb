# typed: strict
# frozen_string_literal: true

require "cmd/pin"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Pin do
  it_behaves_like "parseable arguments"

  it "pins a Formula's version", :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }

    expect { brew "pin", "testball" }.to be_a_success
  end

  it "pins a Cask's version", :cask do
    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)

    expect { described_class.new(["--cask", "local-caffeine"]).run }
      .to not_to_output.to_stderr

    expect(cask).to be_pinned
    expect(cask.pinned_version).to eq("1.2.3")
    cask.unpin
  end

  it "warns when pinning a Cask with auto_updates true", :cask do
    cask = Cask::CaskLoader.load("auto-updates")
    InstallHelper.stub_cask_installation(cask)

    expect do
      described_class.new(["--cask", "auto-updates"]).run
    end.to output(/auto-updates has `auto_updates true`.*outside Homebrew/).to_stderr

    cask.unpin
  end

  it "fails with an uninstalled Formula" do
    package = instance_double(Formula, pinned?: false, pinnable?: false, full_name: "testball")
    cmd = described_class.new(["testball"])
    allow(cmd.args.named).to receive(:to_resolved_formulae_to_casks).and_return([[package], []])

    expect { cmd.run }
      .to output(/testball not installed/).to_stderr
    expect(Homebrew).to have_failed
  end
end
