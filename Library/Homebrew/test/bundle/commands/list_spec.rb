# frozen_string_literal: true

require "bundle"
require "bundle/commands/list"

TYPES_AND_DEPS = {
  taps:     "phinze/cask",
  formulae: "mysql",
  casks:    "google-chrome",
  mas:      "1Password",
  vscode:   "shopify.ruby-lsp",
  go:       "github.com/charmbracelet/crush",
  cargo:    "ripgrep",
}.freeze

COMBINATIONS = begin
  keys = TYPES_AND_DEPS.keys
  1.upto(keys.length).flat_map do |i|
    keys.combination(i).take((1..keys.length).reduce(:*) || 1)
  end.sort
end.freeze

RSpec.describe Homebrew::Bundle::Commands::List do
  subject(:list) do
    described_class.run(
      global:   false,
      file:     nil,
      formulae: formulae,
      casks:    casks,
      taps:     taps,
      mas:      mas,
      vscode:   vscode,
      go:       go,
      cargo:    cargo,
      flatpak:  false,
    )
  end

  let(:formulae) { true }
  let(:casks)    { false }
  let(:taps)     { false }
  let(:mas)      { false }
  let(:vscode)   { false }
  let(:go)       { false }
  let(:cargo)    { false }

  before do
    allow_any_instance_of(IO).to receive(:puts)
  end

  describe "outputs dependencies to stdout" do
    before do
      allow_any_instance_of(Pathname).to receive(:read).and_return(
        <<~EOS,
          tap 'phinze/cask'
          brew 'mysql', conflicts_with: ['mysql56']
          cask 'google-chrome'
          mas '1Password', id: 443987910
          vscode 'shopify.ruby-lsp'
          go 'github.com/charmbracelet/crush'
          cargo 'ripgrep'
        EOS
      )
    end

    it "only shows brew deps when no options are passed" do
      expect { list }.to output("mysql\n").to_stdout
    end

    describe "limiting when certain options are passed" do
      COMBINATIONS.each do |options_list|
        opts_string = options_list.map { |o| "`#{o}`" }.join(" and ")
        verb = (options_list.length == 1) ? "is" : "are"
        words = options_list.join(" and ")

        context "when #{opts_string} #{verb} passed" do
          let(:formulae) { options_list.include?(:formulae) }
          let(:casks)    { options_list.include?(:casks) }
          let(:taps)     { options_list.include?(:taps) }
          let(:mas)      { options_list.include?(:mas) }
          let(:vscode)   { options_list.include?(:vscode) }
          let(:go)       { options_list.include?(:go) }
          let(:cargo)    { options_list.include?(:cargo) }

          it "shows only #{words}" do
            expected = options_list.map { |opt| TYPES_AND_DEPS[opt] }.join("\n")
            expect { list }.to output("#{expected}\n").to_stdout
          end
        end
      end
    end
  end
end
