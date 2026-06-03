# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/subcommand/remove"
require "cask/cask_loader"

RSpec.describe Homebrew::Cmd::Bundle::RemoveSubcommand do
  subject(:remove) do
    klass.new(args_object, context:).run
  end

  let(:klass) { Homebrew::Cmd::Bundle::RemoveSubcommand }
  let(:global) { false }
  let(:context) { bundle_subcommand_context(:remove, global:, file:, no_type_args: type == :none) }

  # These next four `let`s are for the purposes of Sorbet typechecking; the
  # actual values in `args_object` are set by test `let`s.
  let(:type) { :brew }
  let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }
  let(:content) { "dummy content for Sorbet" }
  let(:args) { ["hello"] }

  let(:args_object) do
    args_for_subcommand(:remove, *args, formulae?: type == :brew, casks?: type == :cask, taps?: type == :tap)
  end

  before { File.write(file, content) }
  after { FileUtils.rm_f file }

  context "when called with a valid formula" do
    let(:args) { ["hello"] }
    let(:type) { :brew }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }
    let(:content) do
      <<~BREWFILE
        brew "hello"
      BREWFILE
    end

    before do
      stub_formula_loader(
        formula("hello") do
          url "hello-1.0"
          desc "Program providing model for GNU coding standards and practices"
        end,
      )
    end

    it "removes entries from the given Brewfile" do
      expect { remove }.not_to raise_error
      expect(File.read(file)).not_to include("#{type} \"#{args.first}\"")
    end

    context "when the entry has a preceding description comment" do
      let(:content) do
        <<~BREWFILE
          # Program providing model for GNU coding standards and practices
          brew "hello"
          # Get a file from an HTTP, HTTPS or FTP server
          brew "curl"
        BREWFILE
      end

      it "removes both the entry and its description comment" do
        expect { remove }.not_to raise_error

        expect(File.read(file)).to eq <<~BREWFILE
          # Get a file from an HTTP, HTTPS or FTP server
          brew "curl"
        BREWFILE
      end
    end

    context "when the entry has a preceding comment that's not the entry's description" do
      let(:content) do
        <<~BREWFILE
          # Look at all these nice packages!
          brew "hello"
          # cURL is awesome!
          brew "curl"
        BREWFILE
      end

      it "removes the entry but not the preceding comment" do
        expect { remove }.not_to raise_error

        expect(File.read(file)).to eq <<~BREWFILE
          # Look at all these nice packages!
          # cURL is awesome!
          brew "curl"
        BREWFILE
      end
    end
  end

  context "when called with no type" do
    let(:args) { ["foo"] }
    let(:type) { :none }
    let(:file) { "/tmp/some_random_brewfile#{Random.rand(2 ** 16)}" }
    let(:content) do
      <<~BREWFILE
        tap "someone/tap"
        brew "foo"
        cask "foo"
      BREWFILE
    end

    it "removes all matching entries from the given Brewfile" do
      expect { remove }.not_to raise_error
      expect(File.read(file)).not_to include(args.first)
    end

    context "with arguments that match entries only when considering formula aliases" do
      let(:foo) do
        instance_double(
          Formula,
          name:      "foo",
          full_name: "qux/quuz/foo",
          oldnames:  ["oldfoo"],
          aliases:   ["foobar"],
        )
      end
      let(:args) { ["foobar"] }

      it "suggests using `--formula` to match against formula aliases" do
        expect(Formulary).to receive(:factory).with("foobar").and_return(foo)
        expect { remove }.not_to raise_error
        expect(File.read(file)).to eq(content)
        # FIXME: Why doesn't this work?
        # expect { remove }.to output("--formula").to_stderr
      end
    end
  end
end
