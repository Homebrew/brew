# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/commands/dump"

RSpec.describe Homebrew::Bundle::Commands::Dump do
  subject(:dump) do
    described_class.run(global:, file: nil, describe: false, force:, no_restart: false, taps: true, formulae: true,
                        casks: true, extension_types: { mas: true, vscode: true, cargo: true, flatpak: false,
                                                       go: true, uv: true })
  end

  let(:force) { false }
  let(:global) { false }

  before do
    Homebrew::Bundle::Cask.reset!
    Homebrew::Bundle::Brew.reset!
    Homebrew::Bundle::Tap.reset!
    Homebrew::Bundle::VscodeExtension.reset!
    allow(Homebrew::Bundle::Cargo).to receive(:dump).and_return("")
    allow(Homebrew::Bundle::Uv).to receive(:dump).and_return("")
    allow(Formulary).to receive(:factory).and_call_original
    allow(Formulary).to receive(:factory).with("rust").and_return(
      instance_double(Formula, opt_bin: Pathname.new("/tmp/rust/bin")),
    )
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
      expect(Homebrew::Bundle::Tap).not_to receive(:dump)
      expect(Homebrew::Bundle::Brew).not_to receive(:dump)
      expect(Homebrew::Bundle::Cask).not_to receive(:dump)
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
    end

    it "doesn't raise error" do
      io = instance_double(File, write: true)
      expect_any_instance_of(Pathname).to receive(:open).with("w").and_yield(io)
      expect(io).to receive(:write)
      expect { dump }.not_to raise_error
    end
  end
end
