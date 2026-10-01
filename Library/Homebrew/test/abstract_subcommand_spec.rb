# typed: true
# frozen_string_literal: true

require "abstract_command"
require "abstract_subcommand"

RSpec.describe Homebrew::AbstractSubcommand do
  describe "subclasses" do
    before do
      subcommand = Class.new(Homebrew::AbstractSubcommand) do
        subcommand_args aliases: ["ts"], default: true do
          usage_banner <<~EOS
            `brew test`:
            Run the test subcommand.
          EOS
          switch "--foo"
          named_args :none
        end

        def run; end
      end
      stub_const("TestSubcommand", subcommand)
      stub_const("SubcommandTestCmd", Class.new(Homebrew::AbstractCommand))
    end

    it "defines parser metadata from subcommand_args" do
      parser = Homebrew::CLI::Parser.new(SubcommandTestCmd) do
        TestSubcommand.define(self)
      end

      subcommand = parser.subcommands.fetch(0)
      expect(subcommand.name).to eq("test")
      expect(subcommand.aliases).to eq(["ts"])
      expect(subcommand.default).to be(true)
      expect(parser.processed_options_for_subcommand("test").map(&:second)).to include("--foo")
    end

    it "allows access to args" do
      args = Homebrew::CLI::Args.new
      expect(TestSubcommand.new(args).args).to be_a(Homebrew::CLI::Args)
    end

    it "finds subcommands nested under a command class" do
      nested_subcommand = Class.new(Homebrew::AbstractSubcommand) do
        subcommand_args { named_args :none }
        def run; end
      end
      stub_const("SubcommandTestCmd::NestedSubcommand", nested_subcommand)
      stub_const("OtherSubcommandTestCmd", Class.new(Homebrew::AbstractCommand))
      other_subcommand = Class.new(Homebrew::AbstractSubcommand) do
        subcommand_args { named_args :none }
        def run; end
      end
      stub_const("OtherSubcommandTestCmd::NestedSubcommand", other_subcommand)

      expect(described_class.subcommands_for(SubcommandTestCmd)).to include(nested_subcommand)
      expect(described_class.subcommands_for(SubcommandTestCmd)).not_to include(other_subcommand)
    end

    it "defines all subcommands nested under a command class" do
      stub_const("SubcommandTestCmd::FirstSubcommand", Class.new(Homebrew::AbstractSubcommand) do
        subcommand_args { named_args :none }
        def run; end
      end)
      stub_const("SubcommandTestCmd::SecondSubcommand", Class.new(Homebrew::AbstractSubcommand) do
        subcommand_args { named_args :none }
        def run; end
      end)

      abstract_subcommand = described_class
      parser = Homebrew::CLI::Parser.new(SubcommandTestCmd) do
        abstract_subcommand.define_all(self, command: SubcommandTestCmd)
      end

      expect(parser.subcommand_names).to include("first", "second")
    end

    it "finds its owning command, even when called on the subcommand subclass itself" do
      nested_subcommand = Class.new(Homebrew::AbstractSubcommand) do
        subcommand_args { named_args :none }
        def run; end
      end
      stub_const("SubcommandTestCmd::NestedSubcommand", nested_subcommand)

      expect(nested_subcommand.command).to be(SubcommandTestCmd)
    end

    it "builds a real module and memoizes it" do
      nested_subcommand = Class.new(Homebrew::AbstractSubcommand) do
        subcommand_args { named_args :none }
        def run; end
      end
      stub_const("SubcommandTestCmd::NestedSubcommand", nested_subcommand)

      args_module = nested_subcommand.args_module

      expect(args_module).to be_a(Module)
      expect(nested_subcommand.args_module).to be(args_module)
    end

    it "extends the parsed args with its module, so `is_a?` genuinely holds" do
      nested_subcommand = Class.new(Homebrew::AbstractSubcommand) do
        subcommand_args { named_args :none }
        def run; end
      end
      stub_const("SubcommandTestCmd::NestedSubcommand", nested_subcommand)

      args = Homebrew::CLI::Args.new
      wrapped_args = nested_subcommand.new(args).args

      expect(wrapped_args).to be_a(nested_subcommand.args_module)
      expect(wrapped_args).to be_a(Homebrew::CLI::Args)
    end
  end
end
