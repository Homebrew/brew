# frozen_string_literal: true

require "dev-cmd/determine-test-runners"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::DevCmd::DetermineTestRunners do
  define_method(:get_runners) do |file|
    runner_hash = get_runner_hash(file)
    runner_hash.map { |item| item["runner"].delete_suffix(ephemeral_suffix) }
               .sort
  end

  define_method(:get_runner_hash) do |file|
    runner_line = File.open(file).first
    json_text = runner_line[/runners=(.*)/, 1]
    JSON.parse(json_text)
  end

  after do
    FileUtils.rm_f github_output
  end

  let(:linux_runner) { "ubuntu-22.04" }
  # We need to make sure we write to a different path for each example.
  let(:github_output) { "#{TEST_TMPDIR}/github_output#{DetermineRunnerTestHelper.new.number}" }
  let(:ephemeral_suffix) { "-12345" }
  let(:runner_env) do
    {
      "HOMEBREW_LINUX_RUNNER"       => linux_runner,
      "HOMEBREW_MACOS_LONG_TIMEOUT" => "false",
      "GITHUB_RUN_ID"               => ephemeral_suffix.split("-").second,
    }.freeze
  end
  let(:all_runners) do
    out = []
    MacOSVersion::SYMBOLS.each_value do |v|
      macos_version = MacOSVersion.new(v)
      next if macos_version < GitHubRunnerMatrix::OLDEST_HOMEBREW_CORE_MACOS_RUNNER
      next if macos_version > GitHubRunnerMatrix::NEWEST_HOMEBREW_CORE_MACOS_RUNNER

      out << "#{v}-arm64"
      next if macos_version > GitHubRunnerMatrix::NEWEST_HOMEBREW_CORE_INTEL_MACOS_RUNNER

      out << "#{v}-x86_64"
    end

    out << linux_runner
    out << "#{linux_runner}-arm"

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

  it "rejects dependent shard max runners without `--dependents`", :integration_test do
    expect do
      brew "determine-test-runners", "testball", "--dependent-shard-max-runners=2",
           runner_env.merge({ "GITHUB_OUTPUT" => github_output })
    end.to output(/(?:can only be used with|cannot be passed without) `--dependents`/).to_stderr
                                                                                      .and be_a_failure
  end

  it "rejects dependent shard min dependents per runner without `--dependents`", :integration_test do
    expect do
      brew "determine-test-runners", "testball", "--dependent-shard-min-dependents-per-runner=2",
           runner_env.merge({ "GITHUB_OUTPUT" => github_output })
    end.to output(/(?:can only be used with|cannot be passed without) `--dependents`/).to_stderr
                                                                                      .and be_a_failure
  end

  it "rejects dependent shard runner load factor without `--dependents`", :integration_test do
    expect do
      brew "determine-test-runners", "testball", "--dependent-shard-runner-load-factor=0.8",
           runner_env.merge({ "GITHUB_OUTPUT" => github_output })
    end.to output(/(?:can only be used with|cannot be passed without) `--dependents`/).to_stderr
                                                                                      .and be_a_failure
  end

  it "validates dependent shard max runners as a positive integer", :integration_test do
    expect do
      brew "determine-test-runners", "testball", "--dependents", "--eval-all", "--dependent-shard-max-runners=0",
           runner_env.merge({ "GITHUB_OUTPUT" => github_output })
    end.to output(/must be an integer greater than or equal to 1/).to_stderr
                                                                  .and be_a_failure
  end

  it "validates dependent shard min dependents per runner as a positive integer", :integration_test do
    expect do
      brew "determine-test-runners", "testball", "--dependents", "--eval-all",
           "--dependent-shard-min-dependents-per-runner=0",
           runner_env.merge({ "GITHUB_OUTPUT" => github_output })
    end.to output(/must be an integer greater than or equal to 1/).to_stderr
                                                                  .and be_a_failure
  end

  it "validates dependent shard runner load factor as (0,1]", :integration_test do
    expect do
      brew "determine-test-runners", "testball", "--dependents", "--eval-all",
           "--dependent-shard-runner-load-factor=0",
           runner_env.merge({ "GITHUB_OUTPUT" => github_output })
    end.to output(/must be a number greater than 0 and less than or equal to 1/).to_stderr
                                                                                .and be_a_failure
  end
end

# Generates a unique index for temporary test files.
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
