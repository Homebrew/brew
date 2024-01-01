# frozen_string_literal: true

require "dev-cmd/determine-test-runners"
require "cmd/shared_examples/args_parse"

describe "brew determine-test-runners" do
  after do
    FileUtils.rm_f github_output
  end

  let(:linux_runner) { "ubuntu-22.04" }
  # We need to make sure we write to a different path for each example.
  let(:github_output) { "#{TEST_TMPDIR}/github_output#{DetermineRunnerTestHelper.new.number}" }
  let(:ephemeral_suffix) { "-12345" }
  let(:runner_env) do
    {
      "HOMEBREW_LINUX_RUNNER"  => linux_runner,
      "HOMEBREW_MACOS_TIMEOUT" => "90",
      "GITHUB_RUN_ID"          => ephemeral_suffix.split("-").second,
    }.freeze
  end
  let(:all_runners) do
    out = []
    MacOSVersion::SYMBOLS.each_value do |v|
      macos_version = MacOSVersion.new(v)
      next if macos_version.unsupported_release?

      out << v
      out << "#{v}-arm64"
    end

    out << linux_runner

    out
  end

  it_behaves_like "parseable arguments"

  it "assigns all runners for formulae without any requirements", :integration_test do
    setup_test_formula "testball"

    expect { brew "determine-test-runners", "testball", runner_env.merge({ "GITHUB_OUTPUT" => github_output }) }
      .to not_to_output.to_stderr
      .and be_a_success

    expect(File.read(github_output)).not_to be_empty
    expect(get_runners(github_output).sort).to eq(all_runners.sort)
  end
end

def get_runners(file)
  runner_line = File.open(file).first
  json_text = runner_line[/runners=(.*)/, 1]
  runner_hash = JSON.parse(json_text)
  runner_hash.map { |item| item["runner"].delete_suffix(ephemeral_suffix) }
             .sort
end

class DetermineRunnerTestHelper
  @instances = 0

  class << self
    attr_accessor :instances
  end

  attr_reader :number

  def initialize
    self.class.instances += 1
    @number = self.class.instances
  end
end
