# frozen_string_literal: true

require "release_cooldown"

RSpec.describe Homebrew do
  describe "::release_cooldown_days" do
    it "defaults to 1 day" do
      expect(described_class.release_cooldown_days).to eq 1
    end

    it "respects HOMEBREW_RELEASE_COOLDOWN_DAYS" do
      with_env(HOMEBREW_RELEASE_COOLDOWN_DAYS: "7") do
        expect(described_class.release_cooldown_days).to eq 7
      end
    end

    it "treats 0 as disabling the cooldown" do
      with_env(HOMEBREW_RELEASE_COOLDOWN_DAYS: "0") do
        expect(described_class.release_cooldown_days).to eq 0
      end
    end

    it "clamps negative values to 0" do
      with_env(HOMEBREW_RELEASE_COOLDOWN_DAYS: "-3") do
        expect(described_class.release_cooldown_days).to eq 0
      end
    end

    it "falls back to the default for non-integer values" do
      with_env(HOMEBREW_RELEASE_COOLDOWN_DAYS: "soon") do
        expect(described_class.release_cooldown_days).to eq 1
      end
    end

    it "falls back to the default for empty values" do
      with_env(HOMEBREW_RELEASE_COOLDOWN_DAYS: "") do
        expect(described_class.release_cooldown_days).to eq 1
      end
    end
  end

  describe "::release_cooldown_seconds" do
    it "derives from the configured number of days" do
      with_env(HOMEBREW_RELEASE_COOLDOWN_DAYS: "2") do
        expect(described_class.release_cooldown_seconds).to eq 2 * 24 * 60 * 60
      end
    end
  end
end
