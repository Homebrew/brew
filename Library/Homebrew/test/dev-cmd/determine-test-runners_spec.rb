# typed: true
# frozen_string_literal: true

require "dev-cmd/determine-test-runners"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::DevCmd::DetermineTestRunners do
  def get_runners(file)
    runner_line = File.open(file, &:first).to_s
    json_text = runner_line[/runners=(.*)/, 1].to_s
    runner_hash = JSON.parse(json_text)
    runner_hash.map { |item| item["runner"].delete_suffix(ephemeral_suffix) }
               .sort
  end

  after do
    FileUtils.rm_f github_output
  end

  let(:arm_linux_runner) { OS::LINUX_CI_ARM_RUNNER }
  let(:linux_runner) { "ubuntu-latest" }
  # We need to make sure we write to a different path for each example.
  let(:github_output) { "#{TEST_TMPDIR}/github_output#{DetermineRunnerTestHelper.new.number}" }
  let(:ephemeral_suffix) { "-12345" }
  let(:runner_env) do
    {
      "HOMEBREW_LINUX_RUNNER"       => linux_runner,
      "HOMEBREW_MACOS_LONG_TIMEOUT" => "false",
      "GITHUB_BASE_REF"             => nil,
      "GITHUB_EVENT_NAME"           => nil,
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
    end

    out << linux_runner
    out << arm_linux_runner

    out
  end

  it_behaves_like "parseable arguments"

  it "preserves base-branch transition coverage after the bottle block is removed", :integration_test do
    path = setup_test_formula "testball", bottle_block: <<~RUBY
      bottle do
        sha256 arm64_golden_gate: "#{"a" * 64}"
      end
    RUBY
    repository = CoreTap.instance.path
    Utils.safe_popen_read("git", "-C", repository, "init", "--quiet")
    Utils.safe_popen_read("git", "-C", repository, "add", path)
    Utils.safe_popen_read("git", "-C", repository, "-c", "user.name=Test", "-c", "user.email=test@brew.sh",
                          "commit", "--quiet", "--no-gpg-sign", "-m", "Initial bottle")
    revision = Utils.safe_popen_read("git", "-C", repository, "rev-parse", "HEAD").strip
    Utils.safe_popen_read("git", "-C", repository, "update-ref", "refs/remotes/origin/main", revision)
    Utils.safe_popen_read("git", "-C", repository, "symbolic-ref", "refs/remotes/origin/HEAD",
                          "refs/remotes/origin/main")
    setup_test_formula "testball"

    expect { brew "determine-test-runners", "testball", runner_env.merge({ "GITHUB_OUTPUT" => github_output }) }
      .to not_to_output.to_stderr
      .and be_a_success

    expect(File.read(github_output)).not_to be_empty
    expect(get_runners(github_output).sort).to eq((all_runners + ["27-arm64"]).uniq.sort)
  end
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
