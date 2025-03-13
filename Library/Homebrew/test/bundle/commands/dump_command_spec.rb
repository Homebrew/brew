# frozen_string_literal: true

require "spec_helper"

describe Bundle::Commands::Dump do
  subject(:dump) do
    described_class.run(global:, file: nil, describe: false, force:, no_restart: false, taps: true, brews: true,
                        casks: true, mas: true, whalebrew: true, vscode: true)
  end

  let(:force) { false }
  let(:global) { false }

  context "when files existed" do
    before do
      allow_any_instance_of(Pathname).to receive(:exist?).and_return(true)
      allow(Bundle).to receive(:cask_installed?).and_return(true)
    end

    it "raises error" do
      expect do
        dump
      end.to raise_error(RuntimeError)
    end

    it "exits before doing any work" do
      expect(Bundle::TapDumper).not_to receive(:dump)
      expect(Bundle::BrewDumper).not_to receive(:dump)
      expect(Bundle::CaskDumper).not_to receive(:dump)
      expect(Bundle::WhalebrewDumper).not_to receive(:dump)
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
      allow(Bundle).to receive(:cask_installed?).and_return(true)
    end

    it "doesn't raise error" do
      io = instance_double(File, write: true)
      expect_any_instance_of(Pathname).to receive(:open).with("w").and_yield(io)
      expect(io).to receive(:write)
      expect do
        dump
      end.not_to raise_error
    end
  end
end
