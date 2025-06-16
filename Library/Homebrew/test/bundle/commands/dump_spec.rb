# frozen_string_literal: true

require "bundle"
require "bundle/commands/dump"
require "bundle/cask_dumper"
require "bundle/brew_dumper"
require "bundle/tap_dumper"
require "bundle/whalebrew_dumper"
require "bundle/vscode_extension_dumper"

RSpec.describe Homebrew::Bundle::Commands::Dump do
  subject(:dump) do
    described_class.run(global:, file: nil, describe: false, force:, no_restart: false, taps: true, brews: true,
                        casks: true, mas: true, whalebrew: true, vscode: true)
  end

  let(:force) { false }
  let(:global) { false }

  before do
    Homebrew::Bundle::CaskDumper.reset!
    Homebrew::Bundle::BrewDumper.reset!
    Homebrew::Bundle::TapDumper.reset!
    Homebrew::Bundle::WhalebrewDumper.reset!
    Homebrew::Bundle::VscodeExtensionDumper.reset!
  end

  context "when files existed" do
    before do
      allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
    end

    it "raises error" do
      expect do
        dump
      end.to raise_error(RuntimeError)
    end

    it "exits before doing any work" do
      expect(Homebrew::Bundle::TapDumper).not_to receive(:dump)
      expect(Homebrew::Bundle::BrewDumper).not_to receive(:dump)
      expect(Homebrew::Bundle::CaskDumper).not_to receive(:dump)
      expect(Homebrew::Bundle::WhalebrewDumper).not_to receive(:dump)
      expect do
        dump
      end.to raise_error(RuntimeError)
    end
  end

  context "when files existed and `--force` and `--global` are passed" do
    let(:force) { true }
    let(:global) { true }

    before do
      ENV["HOMEBREW_BUNDLE_FILE"] = ""
      allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
      allow(Cask::Caskroom).to receive(:casks).and_return([])

      # don't try to load gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

      stub_formula_loader formula("mas") { url "mas-1.0" }
      stub_formula_loader formula("whalebrew") { url "whalebrew-1.0" }
    end

    it "doesn't raise error" do
      io = instance_double(File, write: true)
      expect_any_instance_of(Pathname).to receive(:open).with("w").and_yield(io)
      expect(io).to receive(:write)
      expect { dump }.not_to raise_error
    end
  end
end
