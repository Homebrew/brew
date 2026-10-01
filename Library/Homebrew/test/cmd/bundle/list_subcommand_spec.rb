# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/subcommand/list"

TYPES_AND_DEPS = {
  taps:     "phinze/cask",
  formulae: "mysql",
  casks:    "google-chrome",
  mas:      "1Password",
  vscode:   "shopify.ruby-lsp",
  go:       "github.com/charmbracelet/crush",
  cargo:    "ripgrep",
  uv:       "mkdocs",
}.freeze

COMBINATIONS = begin
  keys = TYPES_AND_DEPS.keys
  1.upto(keys.length).flat_map do |i|
    keys.combination(i).take((1..keys.length).reduce(:*) || 1)
  end.sort
end.freeze

RSpec.describe Homebrew::Cmd::Bundle::ListSubcommand do
  subject(:list) do
    described_class.new(args_object, context:).run
  end

  let(:context) { bundle_subcommand_context(:list, no_type_args:) }
  let(:args_object) do
    args_for_subcommand(:list, formulae?: formulae, casks?: casks, taps?: taps, mas?: mas, vscode?: vscode,
                               cargo?: cargo, flatpak?: false, go?: go, uv?: uv, all?: false)
  end
  let(:no_type_args) { [formulae, casks, taps, mas, vscode, go, cargo, uv].none? }
  let(:formulae) { false }
  let(:casks)    { false }
  let(:taps)     { false }
  let(:mas)      { false }
  let(:vscode)   { false }
  let(:go)       { false }
  let(:cargo)    { false }
  let(:uv)       { false }

  before do
    allow_any_instance_of(IO).to receive(:puts)
  end

  describe "outputs dependencies to stdout" do
    before do
      allow_any_instance_of(Pathname).to receive(:read).and_return(
        <<~RUBY,
          tap 'phinze/cask'
          brew 'mysql', conflicts_with: ['mysql56']
          cask 'google-chrome'
          mas '1Password', id: 443987910
          vscode 'shopify.ruby-lsp'
          go 'github.com/charmbracelet/crush'
          cargo 'ripgrep'
          uv 'mkdocs'
        RUBY
      )
    end

    it "only shows brew deps when no options are passed" do
      expect { list }.to output("mysql\n").to_stdout
    end

    describe "limiting when certain options are passed" do
      it "shows only the requested type(s) for all combinations" do
        COMBINATIONS.each do |options_list|
          formulae = options_list.include?(:formulae)
          casks = options_list.include?(:casks)
          taps = options_list.include?(:taps)
          mas = options_list.include?(:mas)
          vscode = options_list.include?(:vscode)
          go = options_list.include?(:go)
          cargo = options_list.include?(:cargo)
          uv = options_list.include?(:uv)

          no_type_args = [formulae, casks, taps, mas, vscode, go, cargo, uv].none?
          context = bundle_subcommand_context(:list, no_type_args:)
          args_object = args_for_subcommand(
            :list,
            formulae?: formulae,
            casks?:    casks,
            taps?:     taps,
            mas?:      mas,
            vscode?:   vscode,
            cargo?:    cargo,
            flatpak?:  false,
            go?:       go,
            uv?:       uv,
            all?:      false,
          )

          expected = options_list.map { |opt| TYPES_AND_DEPS[opt] }.join("\n")
          expect do
            described_class.new(args_object, context:).run
          end.to output("#{expected}\n").to_stdout
        end
      end
    end
  end
end
