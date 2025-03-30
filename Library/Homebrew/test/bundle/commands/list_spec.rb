# frozen_string_literal: true

require "bundle"
require "bundle/commands/list"

RSpec.describe Homebrew::Bundle::Commands::List do
  subject(:list) { described_class.run(global: false, file: nil, brews:, casks:, taps:, mas:, whalebrew:, vscode:) }

  let(:brews) { true }
  let(:casks) { false }
  let(:taps) { false }
  let(:mas) { false }
  let(:whalebrew) { false }
  let(:vscode) { false }

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
          whalebrew 'whalebrew/imagemagick'
          vscode 'shopify.ruby-lsp'
        EOS
      )
    end

    it "only shows brew deps when no options are passed" do
      expect { list }.to output("mysql\n").to_stdout
    end

    describe "limiting when certain options are passed" do
      types_and_deps = {
        taps:      "phinze/cask",
        brews:     "mysql",
        casks:     "google-chrome",
        mas:       "1Password",
        whalebrew: "whalebrew/imagemagick",
        vscode:    "shopify.ruby-lsp",
      }

      combinations = 1.upto(types_and_deps.length).flat_map do |i|
        types_and_deps.keys.combination(i).take((1..types_and_deps.length).reduce(:*) || 1)
      end.sort

      combinations.each do |options_list|
        args_hash = options_list.to_h { |arg| [arg, true] }
        words = options_list.join(" and ")
        opts = options_list.map { |o| "`#{o}`" }.join(" and ")
        verb = (options_list.length == 1 && "is") || "are"

        context "when #{opts} #{verb} passed" do
          let(:brews) { args_hash[:brews] }
          let(:casks) { args_hash[:casks] }
          let(:taps) { args_hash[:taps] }
          let(:mas) { args_hash[:mas] }
          let(:whalebrew) { args_hash[:whalebrew] }
          let(:vscode) { args_hash[:vscode] }

          it "shows only #{words}" do
            expected = options_list.map { |opt| types_and_deps[opt] }.join("\n")
            expect { list }.to output("#{expected}\n").to_stdout
          end
        end
      end
    end
  end
end
