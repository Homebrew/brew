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
  let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }
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

  context "when called with a fully-qualified formula from an untapped tap" do
    let(:args) { ["user/repo/hello"] }
    let(:type) { :brew }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }
    let(:events) { [] }

    before do
      tap = Tap.fetch("user", "repo")
      formula_instance = formula("hello") do
        T.bind(self, T.class_of(Formula))
        url "hello-1.0"
      end

      allow(Tap).to receive(:with_formula_name).with(args.first).and_return([tap, "hello"])
      allow(tap).to receive(:ensure_installed!) { events << :tap }
      allow(Homebrew::Trust).to receive(:trust_fully_qualified_items!).with(args, type: :formula) do
        events << :trust
      end
      allow(Formulary).to receive(:factory).with(args.first) do
        events << :load
        formula_instance
      end
    end

    it "installs and trusts the tap before loading the formula" do
      add
      expect(events).to eq([:tap, :trust, :load])
    end
  end

  context "when called with a fully-qualified cask from an untapped tap" do
    let(:args) { ["user/repo/alacritty"] }
    let(:type) { :cask }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }
    let(:events) { [] }

    before do
      tap = Tap.fetch("user", "repo")
      cask = Cask::CaskLoader::FromContentLoader.new(+<<~RUBY).load(config: nil)
        cask "alacritty" do
          version "1.0"
        end
      RUBY

      allow(Tap).to receive(:with_cask_token).with(args.first).and_return([tap, "alacritty"])
      allow(tap).to receive(:ensure_installed!) { events << :tap }
      allow(Homebrew::Trust).to receive(:trust_fully_qualified_items!).with(args, type: :cask) do
        events << :trust
      end
      allow(Cask::CaskLoader).to receive(:load).with(args.first) do
        events << :load
        cask
      end
    end

    it "installs and trusts the tap before loading the cask" do
      add
      expect(events).to eq([:tap, :trust, :load])
    end
  end

  it "adds a cask and its description comment", :cask, :integration_test do
    mktmpdir do |path|
      brewfile = path/"Brewfile"
      brewfile.write ""

      expect { brew "bundle", "add", "local-transmission", "--cask", "--file=#{brewfile}" }
        .to not_to_output.to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
      expect(brewfile.read).to eq <<~BREWFILE
        # BitTorrent client
        cask "local-transmission"
      BREWFILE
    end
  end
end
