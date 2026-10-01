# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/subcommand/dump"

RSpec.describe Homebrew::Cmd::Bundle::DumpSubcommand do
  subject(:dump) do
    described_class.new(args_object, context:).run
  end

  let(:force) { false }
  let(:global) { false }
  let(:context) { bundle_subcommand_context(:dump, global:, force:, no_type_args: false) }
  let(:args_object) do
    args_for_subcommand(:dump, describe?: false, no_restart?: false, taps?: true, formulae?: true, casks?: true,
                               mas?: true, vscode?: true, cargo?: true, flatpak?: false, go?: true, uv?: true)
  end

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

  it "does not dump disabled types by default" do
    args_object = args_for_subcommand(:dump, describe?: false, no_restart?: false, no_formulae?: true, no_mas?: true)
    context = bundle_subcommand_context(:dump)

    expect(Homebrew::Bundle::Dumper).to receive(:dump_brewfile) do |formulae:, casks:, taps:, extension_types:, **|
      expect(formulae).to be(false)
      expect(casks).to be(true)
      expect(taps).to be(true)
      expect(extension_types[:mas]).to be(false)
      expect(extension_types[:vscode]).to be(true)
    end

    described_class.new(args_object, context:).run
  end

  it "treats --no-tap as --no-dump-tap" do
    args_object = args_for_subcommand(:dump, describe?: false, no_restart?: false, no_taps?: true)
    context = bundle_subcommand_context(:dump)

    expect(Homebrew::Bundle::Dumper).to receive(:dump_brewfile) do |taps:, **|
      expect(taps).to be(false)
    end

    described_class.new(args_object, context:).run
  end

  it "does not dump types disabled by environment" do
    args_object = args_for_subcommand(:dump, describe?: false, no_restart?: false, no_dump_brew?: true,
                                             no_dump_mas?: true)
    context = bundle_subcommand_context(:dump)

    expect(Homebrew::Bundle::Dumper).to receive(:dump_brewfile) do |formulae:, casks:, taps:, extension_types:, **|
      expect(formulae).to be(false)
      expect(casks).to be(true)
      expect(taps).to be(true)
      expect(extension_types[:mas]).to be(false)
      expect(extension_types[:vscode]).to be(true)
    end

    described_class.new(args_object, context:).run
  end

  context "when files existed and `--force` and `--global` are passed" do
    let(:force) { true }
    let(:global) { true }

    before do
      ENV["HOMEBREW_BUNDLE_FILE"] = ""
      stub_formula_loader formula("mas") {
        T.bind(self, T.class_of(Formula))
        url "mas-1.0"
      }
      allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
      allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
      allow(Cask::Caskroom).to receive(:casks).and_return([])

      # don't try to load gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)
    end

    it "doesn't raise error" do
      io = instance_double(File, write: true)
      expect_any_instance_of(Pathname).to receive(:open).with("w").and_yield(io)
      expect(io).to receive(:write)
      expect { dump }.not_to raise_error
    end
  end
end
