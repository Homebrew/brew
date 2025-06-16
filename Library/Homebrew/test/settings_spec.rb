# frozen_string_literal: true

require "settings"

RSpec.describe Homebrew::Settings do
  before do
    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
    end
  end

  def setup_setting
    HOMEBREW_REPOSITORY.cd do
      system "git", "config", "--replace-all", "homebrew.foo", "true"
    end
  end

  describe ".read" do
    it "returns the correct value for a setting" do
      setup_setting
      expect(described_class.read("foo")).to eq "true"
    end

    it "returns the correct value for a setting as a symbol" do
      setup_setting
      expect(described_class.read(:foo)).to eq "true"
    end

    it "returns nil when setting is not set" do
      setup_setting
      expect(described_class.read("bar")).to be_nil
    end

    it "runs on a repo without a configuration file" do
      expect { described_class.read("foo", repo: HOMEBREW_REPOSITORY/"bar") }.not_to raise_error
    end
  end

  describe ".write" do
    it "writes over an existing value" do
      setup_setting
      described_class.write :foo, false
      expect(described_class.read("foo")).to eq "false"
    end

    it "writes a new value" do
      setup_setting
      described_class.write :bar, "abcde"
      expect(described_class.read("bar")).to eq "abcde"
    end

    it "returns if the repo doesn't have a configuration file" do
      expect { described_class.write("foo", false, repo: HOMEBREW_REPOSITORY/"bar") }.not_to raise_error
    end
  end

  describe ".delete" do
    it "deletes an existing setting" do
      setup_setting
      described_class.delete(:foo)
      expect(described_class.read("foo")).to be_nil
    end

    it "deletes a non-existing setting" do
      setup_setting
      expect { described_class.delete(:bar) }.not_to raise_error
    end

    it "returns if the repo doesn't have a configuration file" do
      expect { described_class.delete("foo", repo: HOMEBREW_REPOSITORY/"bar") }.not_to raise_error
    end
  end
end
