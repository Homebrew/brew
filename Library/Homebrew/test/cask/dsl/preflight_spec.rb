# typed: true
# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"
require "test/cask/dsl/shared_examples/staged"

RSpec.describe Cask::DSL::Preflight, :cask do
  subject(:dsl) { described_class.new(cask, fake_system_command) }

  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }
  let(:fake_system_command) { class_double(SystemCommand) }

  it_behaves_like Cask::DSL::Base

  it_behaves_like Cask::Staged

  it "changes ownership without sudo when sudo is disabled" do
    ENV["HOMEBREW_NO_SUDO"] = "1"
    path = mktmpdir/"owned"
    path.write ""

    expect(fake_system_command).to receive(:run!)
      .with("chown", args: ["-R", "--", "#{User.current}:staff", path], sudo: nil)

    dsl.set_ownership(path.to_s)
  end
end
