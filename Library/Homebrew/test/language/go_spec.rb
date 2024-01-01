# frozen_string_literal: true

require "language/go"

describe Language::Go do
  specify "#stage_deps" do
    ENV.delete("HOMEBREW_DEVELOPER")

    expect(described_class).to receive(:opoo).once

    mktmpdir do |path|
      described_class.stage_deps [], path
    end
  end
end
