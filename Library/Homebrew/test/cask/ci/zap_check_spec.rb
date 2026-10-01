# typed: strict
# frozen_string_literal: true

require "cask/cask"
require "cask/ci/zap_check"

RSpec.describe Cask::CI::ZapCheck do
  it "recognises paths covered by zap directives" do
    cask = Cask::Cask.new("cask-ci-test") do
      zap trash: ["~/Library/Application Support/Cask CI Test", "~/Library/Preferences/*.plist"],
          rmdir: "~/Library/Caches/Cask CI Test"
    end
    generated_paths = [
      "~/Library/Application Support/Cask CI Test",
      "~/Library/Application Support/Cask CI Test/State",
      "~/Library/Preferences/com.example.cask-ci-test.plist",
      "~/Library/Caches/Cask CI Test",
      "~/Library/Caches/Cask CI Test/State",
      "~/Library/Logs/Cask CI Test.log",
    ]

    expect(described_class.reject_covered(cask, generated_paths)).to eq([
      "~/Library/Caches/Cask CI Test/State",
      "~/Library/Logs/Cask CI Test.log",
    ])
  end

  it "matches descendants case-insensitively" do
    expect(described_class.descendant?("~/library/test/State", of: "~/Library/Test")).to be true
  end

  it "matches generated wildcard paths against literal directives" do
    expect(described_class.covers?("~/Library/Test/1234", "~/Library/Test/*")).to be true
  end

  it "escapes application paths for process matching" do
    app = Pathname("/Applications/Cask CI (Test).app")

    expect(described_class.process_pattern(app)).to eq("^/Applications/Cask\\ CI\\ \\(Test\\)\\.app/")
  end

  it "returns immediately when a condition is met" do
    expect(described_class.wait_until(1) { true }).to be true
  end

  it "reports findings without failing the command" do
    expect do
      described_class.report("Casks/cask-ci-test.rb", "Possible missing paths:", "~/Library/Cask CI Test")
    end.not_to change(Homebrew, :failed?)
  end

  it "appends findings to the step summary" do
    mktmpdir do |path|
      summary = path/"summary.md"
      ENV["GITHUB_STEP_SUMMARY"] = summary.to_s

      described_class.report("Casks/cask-ci-test.rb", "Possible missing paths:", "~/Library/Cask CI Test")

      expect(summary.read).to include("## Possible missing zap paths", "~/Library/Cask CI Test")
    end
  end
end
