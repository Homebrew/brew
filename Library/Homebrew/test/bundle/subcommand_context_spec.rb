# typed: true
# frozen_string_literal: true

require "abstract_command"
require "abstract_subcommand"
require "bundle/subcommand_context"

RSpec.describe Homebrew::Cmd::Bundle::SubcommandContextReader do
  before do
    stub_const("SubcommandContextReaderTestCmd", Class.new(Homebrew::AbstractCommand))
    stub_const("SubcommandContextReaderTestCmd::TestSubcommand", Class.new(Homebrew::AbstractSubcommand) do
      include Homebrew::Cmd::Bundle::SubcommandContextReader

      subcommand_args { named_args :none }
      def run; end
    end)
  end

  let(:context) do
    Homebrew::Cmd::Bundle::SubcommandContext.new(
      subcommand: "test", global: false, file: nil, no_upgrade: false, verbose: false,
      force: false, ask: false, zap: false, no_type_args: true, extensions: []
    )
  end

  it "returns the context it was constructed with" do
    subcommand = SubcommandContextReaderTestCmd::TestSubcommand.new(Homebrew::CLI::Args.new, context:)

    expect(subcommand.context).to be(context)
  end

  it "raises when constructed without a context" do
    subcommand = SubcommandContextReaderTestCmd::TestSubcommand.new(Homebrew::CLI::Args.new)

    expect { subcommand.context }.to raise_error(TypeError)
  end
end
