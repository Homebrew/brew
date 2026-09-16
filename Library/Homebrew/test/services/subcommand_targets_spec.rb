# typed: true
# frozen_string_literal: true

require "abstract_command"
require "abstract_subcommand"
require "services/subcommand_targets"

RSpec.describe Homebrew::Cmd::Services::SubcommandTargetsReader do
  before do
    stub_const("SubcommandTargetsReaderTestCmd", Class.new(Homebrew::AbstractCommand))
    stub_const("SubcommandTargetsReaderTestCmd::TestSubcommand", Class.new(Homebrew::AbstractSubcommand) do
      include Homebrew::Cmd::Services::SubcommandTargetsReader

      subcommand_args { named_args :none }
      def run; end
    end)
  end

  it "returns the targets it was constructed with" do
    subcommand = SubcommandTargetsReaderTestCmd::TestSubcommand.new(Homebrew::CLI::Args.new, targets: [])

    expect(subcommand.targets).to eq([])
  end

  it "raises when constructed without targets" do
    subcommand = SubcommandTargetsReaderTestCmd::TestSubcommand.new(Homebrew::CLI::Args.new)

    expect { subcommand.targets }.to raise_error(TypeError)
  end
end
