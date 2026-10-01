# typed: true
# frozen_string_literal: true

RSpec.describe Test::Helper::IntegrationTest do
  subject(:helper) { Object.new.extend(described_class) }

  let(:status) { instance_double(Process::Status) }

  before do
    allow(helper).to receive(:command_id).and_return("integration-command")
  end

  around do |example|
    (HOMEBREW_PREFIX/"bin").mkpath
    example.run
  ensure
    FileUtils.rm_rf [HOMEBREW_PREFIX/"bin", HOMEBREW_PREFIX/"Library/Homebrew"]
  end

  it "copies an executable Homebrew entry point into the test prefix" do
    FileUtils.touch HOMEBREW_PREFIX/"bin/brew"
    brew_sh_path = Pathname(helper.test_prefix_brew_sh)

    expect([brew_sh_path.symlink?, brew_sh_path.executable?, brew_sh_path.read])
      .to eq([false, true, HOMEBREW_BREW_FILE.read])
  end

  it "disables Sorbet checking in Ruby integration commands" do
    captured_env = {}
    allow(Open3).to receive(:capture3) do |env, *_args|
      captured_env.replace(env)
      ["", "", status]
    end

    helper.brew "help"

    expect(captured_env.slice("HOMEBREW_SORBET_RUNTIME", "HOMEBREW_SORBET_RECURSIVE")).to eq(
      "HOMEBREW_SORBET_RUNTIME"   => nil,
      "HOMEBREW_SORBET_RECURSIVE" => nil,
    )
  end

  it "uses the lightweight integration coverage recorder" do
    ENV["HOMEBREW_TESTS_COVERAGE"] = "1"
    captured_command = []
    allow(Open3).to receive(:capture3) do |_env, *command|
      captured_command.replace(command.map(&:to_s))
      ["", "", status]
    end

    helper.brew "help"

    expect([
      captured_command.any? { |arg| arg.include?("integration_coverage") },
      captured_command.any? { |arg| arg.include?("simplecov_start") },
    ]).to eq([true, false])
  end
end
