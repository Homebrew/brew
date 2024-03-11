# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::EnvConfig do
  subject(:env_config) { described_class }

  describe ".env_method_name" do
    it "generates method names" do
      expect(env_config.env_method_name("HOMEBREW_FOO", {})).to eql("foo")
    end

    it "generates boolean method names" do
      expect(env_config.env_method_name("HOMEBREW_BAR", boolean: true)).to eql("bar?")
    end
  end

  describe ".artifact_domain" do
    it "returns value if set" do
      ENV["HOMEBREW_ARTIFACT_DOMAIN"] = "https://brew.sh"
      expect(env_config.artifact_domain).to eql("https://brew.sh")
    end

    it "returns nil if empty" do
      ENV["HOMEBREW_ARTIFACT_DOMAIN"] = ""
      expect(env_config.artifact_domain).to be_nil
    end
  end

  describe ".cleanup_periodic_full_days" do
    it "returns value if set" do
      ENV["HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS"] = "360"
      expect(env_config.cleanup_periodic_full_days).to eql("360")
    end

    it "returns default if unset" do
      ENV["HOMEBREW_CLEANUP_PERIODIC_FULL_DAYS"] = nil
      expect(env_config.cleanup_periodic_full_days).to eql("30")
    end
  end

  describe ".bat?" do
    it "returns true if set" do
      ENV["HOMEBREW_BAT"] = "1"
      expect(env_config.bat?).to be(true)
    end

    it "returns false if unset" do
      ENV["HOMEBREW_BAT"] = nil
      expect(env_config.bat?).to be(false)
    end
  end

  describe ".make_jobs" do
    it "returns value if positive" do
      ENV["HOMEBREW_MAKE_JOBS"] = "4"
      expect(env_config.make_jobs).to eql("4")
    end

    it "returns default if negative" do
      ENV["HOMEBREW_MAKE_JOBS"] = "-1"
      expect(Hardware::CPU).to receive(:cores).and_return(16)
      expect(env_config.make_jobs).to eql("16")
    end
  end

  describe ".cask_upgrade_greedy" do
    it "returns true if \"HOMEBREW_UPGRADE_GREEDY\" set to \"1\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "1"
      expect(env_config.cask_upgrade_greedy?).to be(true)
    end

    it "returns true if \"HOMEBREW_UPGRADE_GREEDY\" set to \"true\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "true"
      expect(env_config.cask_upgrade_greedy?).to be(true)
    end

    it "returns false if \"HOMEBREW_UPGRADE_GREEDY\" set to \"latest\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "latest"
      expect(env_config.cask_upgrade_greedy?).to be(false)
    end

    it "returns false if \"HOMEBREW_UPGRADE_GREEDY\" set to \"auto-updates\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "auto-updates"
      expect(env_config.cask_upgrade_greedy?).to be(false)
    end

    it "returns false by default" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = ""
      expect(env_config.cask_upgrade_greedy?).to be(false)
    end
  end

  describe ".cask_upgrade_greedy_latest" do
    it "returns false if \"HOMEBREW_UPGRADE_GREEDY\" set to \"1\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "1"
      expect(env_config.cask_upgrade_greedy_latest?).to be(false)
    end

    it "returns false if \"HOMEBREW_UPGRADE_GREEDY\" set to \"true\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "true"
      expect(env_config.cask_upgrade_greedy_latest?).to be(false)
    end

    it "returns true if \"HOMEBREW_UPGRADE_GREEDY\" set to \"latest\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "latest"
      expect(env_config.cask_upgrade_greedy_latest?).to be(true)
    end

    it "returns false if \"HOMEBREW_UPGRADE_GREEDY\" set to \"auto-updates\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "auto-updates"
      expect(env_config.cask_upgrade_greedy_latest?).to be(false)
    end

    it "returns false by default" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = ""
      expect(env_config.cask_upgrade_greedy_latest?).to be(false)
    end
  end

  describe ".cask_upgrade_greedy_auto_updates" do
    it "returns false if \"HOMEBREW_UPGRADE_GREEDY\" set to \"1\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "1"
      expect(env_config.cask_upgrade_greedy_auto_updates?).to be(false)
    end

    it "returns false if \"HOMEBREW_UPGRADE_GREEDY\" set to \"true\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "true"
      expect(env_config.cask_upgrade_greedy_auto_updates?).to be(false)
    end

    it "returns false if \"HOMEBREW_UPGRADE_GREEDY\" set to \"latest\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "latest"
      expect(env_config.cask_upgrade_greedy_auto_updates?).to be(false)
    end

    it "returns true if \"HOMEBREW_UPGRADE_GREEDY\" set to \"auto-updates\"" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = "auto-updates"
      expect(env_config.cask_upgrade_greedy_auto_updates?).to be(true)
    end

    it "returns false by default" do
      ENV["HOMEBREW_UPGRADE_GREEDY"] = ""
      expect(env_config.cask_upgrade_greedy_auto_updates?).to be(false)
    end
  end
end
