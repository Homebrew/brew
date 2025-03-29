# frozen_string_literal: true

require "bundle"
require "bundle/commands/add"
require "cask/cask_loader"

RSpec.describe Homebrew::Bundle::Commands::Add do
  subject(:add) do
    described_class.run(*args, type:, global:, file:)
  end

  before { FileUtils.touch file }
  after { FileUtils.rm_f file }

  let(:global) { false }

  context "when called with a valid formula" do
    let(:args) { ["hello"] }
    let(:type) { :brew }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }

    before do
      stub_formula_loader formula("hello") { url "hello-1.0" }
    end

    it "adds entries to the given Brewfile" do
      expect { add }.not_to raise_error
      expect(File.read(file)).to include("#{type} \"#{args.first}\"")
    end
  end

  context "when called with a valid cask" do
    let(:args) { ["alacritty"] }
    let(:type) { :cask }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }

    before do
      stub_cask_loader Cask::CaskLoader::FromContentLoader.new(+<<~RUBY).load(config: nil)
        cask "alacritty" do
          version "1.0"
        end
      RUBY
    end

    it "adds entries to the given Brewfile" do
      expect { add }.not_to raise_error
      expect(File.read(file)).to include("#{type} \"#{args.first}\"")
    end
  end
end
