# typed: strict
# frozen_string_literal: true

RSpec.shared_examples "parseable arguments" do |command_name: nil|
  it "can parse arguments" do
    if described_class
      klass = described_class
    else
      # for tests of remote taps, we need to load the command class
      command_path = Commands.external_ruby_v2_cmd_path(command_name)
      raise "Unable to find command #{command_name}" if command_path.nil?

      require(command_path)
      example = RSpec.current_example
      raise "Unable to determine the current example" if example.nil?

      command = example.metadata.dig(:example_group, :parent_example_group, :description)
      raise "Unable to determine the command class" unless command.is_a?(String)

      # The command class name is only known at runtime.
      # rubocop:disable Sorbet/ConstantsFromStrings
      klass = Object.const_get(command)
      # rubocop:enable Sorbet/ConstantsFromStrings
    end
    argv = klass.parser.min_named_args&.times&.map { "argument" } || []
    cmd = klass.new(argv)
    expect(cmd.args).to be_a Homebrew::CLI::Args
  end
end
