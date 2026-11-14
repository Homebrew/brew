# typed: strict
# frozen_string_literal: true

require "livecheck/progress"

RSpec.describe Homebrew::Livecheck::Progress do
  it "keeps non-interactive checks silent" do
    expect do
      progress = described_class.new(total: 1, enabled: false)
      progress.increment
      progress.finish
    end.not_to output.to_stderr
  end

  it "labels interactive checks on stderr" do
    expect do
      progress = described_class.new(total: 1, enabled: true)
      progress.increment
      progress.finish
    end.to output(include("Running checks")).to_stderr
  end
end
