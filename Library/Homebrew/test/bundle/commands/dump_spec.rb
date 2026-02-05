# frozen_string_literal: true

require "bundle"
require "bundle/commands/dump"
require "bundle/cask_dumper"
require "bundle/formula_dumper"
require "bundle/tap_dumper"
require "bundle/vscode_extension_dumper"
require "bundle/cargo_dumper"

RSpec.describe Homebrew::Bundle::Commands::Dump do
  subject(:dump) do
    described_class.run(global:, file: nil, describe: false, force:, no_restart: false, taps: true, formulae: true,
                        casks: true, mas: true, vscode: true, go: true, cargo: true, flatpak: false)
  end

  let(:force) { false }
  let(:global) { false }

  before do
    Homebrew::Bundle::CaskDumper.reset!
    Homebrew::Bundle::FormulaDumper.reset!
    Homebrew::Bundle::TapDumper.reset!
    Homebrew::Bundle::VscodeExtensionDumper.reset!
    allow(Homebrew::Bundle::CargoDumper).to receive(:dump).and_return("")
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
      expect(Homebrew::Bundle::TapDumper).not_to receive(:dump)
      expect(Homebrew::Bundle::FormulaDumper).not_to receive(:dump)
      expect(Homebrew::Bundle::CaskDumper).not_to receive(:dump)
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
