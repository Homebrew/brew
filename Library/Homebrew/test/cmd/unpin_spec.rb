# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cmd/unpin"

RSpec.describe Homebrew::Cmd::Unpin do
  it_behaves_like "parseable arguments"

  it "unpins a Formula's version", :integration_test do
    setup_test_formula "testball", tab_attributes: { installed_on_request: true }
    Formula["testball"].pin

    expect { brew "unpin", "testball" }.to be_a_success
  end

  it "unpins a Cask's version", :cask do
    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)
    cask.pin

    expect { described_class.new(["--cask", "local-caffeine"]).run }
      .to not_to_output.to_stderr

    expect(cask).not_to be_pinned
  end

  it "removes a dangling Cask pin", :cask do
    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)
    cask.pin
    FileUtils.rm_r(cask.caskroom_path/"1.2.3")

    expect(cask).not_to be_pinned
    expect(cask.pin_path).to be_a_symlink

    expect { described_class.new(["--cask", "local-caffeine"]).run }
      .to not_to_output.to_stderr

    expect(cask.pin_path).not_to be_a_symlink
  end
end
