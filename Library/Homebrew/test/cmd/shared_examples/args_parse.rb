# frozen_string_literal: true

RSpec.shared_examples "parseable arguments" do |command_name: nil|
  let(:command) do |example|
    example.metadata.dig(:example_group, :parent_example_group, :description)
  end

  it "can parse arguments" do
    if described_class
      klass = described_class
    else
      # for tests of remote taps, we need to load the command class
      require(Commands.external_ruby_v2_cmd_path(command_name))
      klass = Object.const_get(command)
    end
    argv = klass.parser.instance_variable_get(:@min_named_args)&.times&.map { "argument" } || []
    cmd = klass.new(argv)
    expect(cmd.args).to be_a Homebrew::CLI::Args
  end
end
