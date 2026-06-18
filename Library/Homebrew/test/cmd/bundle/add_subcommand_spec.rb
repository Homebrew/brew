# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/subcommand/add"
require "cask/cask_loader"

RSpec.describe Homebrew::Cmd::Bundle::AddSubcommand do
  subject(:add) do
    described_class.new(args_object, context:).run
  end

  let(:global) { false }
  let(:context) { bundle_subcommand_context(:add, global:, file:, no_type_args: false) }
  let(:args_object) do
    args_for_subcommand(:add, *args, formulae?: type == :brew, casks?: type == :cask, taps?: type == :tap,
                                      describe?: false)
  end

  before { FileUtils.touch file }
  after { FileUtils.rm_f file }

  context "when called with a valid formula" do
    let(:args) { ["hello"] }
    let(:type) { :brew }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }

    before do
      stub_formula_loader(
        formula("hello") do
          T.bind(self, T.class_of(Formula))
          url "hello-1.0"
        end,
      )
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
