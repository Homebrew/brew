# frozen_string_literal: true

require "rubocops/rubocop-cask"

describe RuboCop::Cop::Cask::Variables, :config do
  it "accepts when there are no variables" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version :latest
      end
    CASK
  end

  it "accepts when there is an `arch` stanza" do
    expect_no_offenses <<~CASK
      cask "foo" do
        arch arm: "darwin-arm64", intel: "darwin"
      end
    CASK
  end

  it "accepts an `on_arch_conditional` variable" do
    expect_no_offenses <<~CASK
      cask "foo" do
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
      end
    CASK
  end

  it "reports an offense for an `arch` variable using strings" do
    expect_offense <<~CASK
      cask 'foo' do
        arch = Hardware::CPU.intel? ? "darwin" : "darwin-arm64"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `arch arm: "darwin-arm64", intel: "darwin"` instead of `arch = Hardware::CPU.intel? ? "darwin" : "darwin-arm64"`.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "darwin-arm64", intel: "darwin"
      end
    CASK
  end

  it "reports an offense for an `arch` variable using symbols" do
    expect_offense <<~CASK
      cask 'foo' do
        arch = Hardware::CPU.intel? ? :darwin : :darwin_arm64
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `arch arm: :darwin_arm64, intel: :darwin` instead of `arch = Hardware::CPU.intel? ? :darwin : :darwin_arm64`.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: :darwin_arm64, intel: :darwin
      end
    CASK
  end

  it "reports an offense for an `arch` variable with an empty string" do
    expect_offense <<~CASK
      cask 'foo' do
        arch = Hardware::CPU.intel? ? "" : "arm64"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `arch arm: "arm64"` instead of `arch = Hardware::CPU.intel? ? "" : "arm64"`.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "arm64"
      end
    CASK
  end

  it "reports an offense for a non-`arch` variable using strings" do
    expect_offense <<~CASK
      cask 'foo' do
        folder = Hardware::CPU.intel? ? "darwin" : "darwin-arm64"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"` instead of `folder = Hardware::CPU.intel? ? "darwin" : "darwin-arm64"`.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
      end
    CASK
  end

  it "reports an offense for a non-`arch` variable with an empty string" do
    expect_offense <<~CASK
      cask 'foo' do
        folder = Hardware::CPU.intel? ? "amd64" : ""
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `folder = on_arch_conditional intel: "amd64"` instead of `folder = Hardware::CPU.intel? ? "amd64" : ""`.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        folder = on_arch_conditional intel: "amd64"
      end
    CASK
  end

  it "reports an offense for consecutive `arch` and non-`arch` variables" do
    expect_offense <<~CASK
      cask 'foo' do
        arch = Hardware::CPU.arm? ? "darwin-arm64" : "darwin"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `arch arm: "darwin-arm64", intel: "darwin"` instead of `arch = Hardware::CPU.arm? ? "darwin-arm64" : "darwin"`.
        folder = Hardware::CPU.arm? ? "darwin-arm64" : "darwin"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"` instead of `folder = Hardware::CPU.arm? ? "darwin-arm64" : "darwin"`.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        arch arm: "darwin-arm64", intel: "darwin"
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
      end
    CASK
  end

  it "reports an offense for two consecutive non-`arch` variables" do
    expect_offense <<~CASK
      cask 'foo' do
        folder = Hardware::CPU.arm? ? "darwin-arm64" : "darwin"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"` instead of `folder = Hardware::CPU.arm? ? "darwin-arm64" : "darwin"`.
        platform = Hardware::CPU.intel? ? "darwin": "darwin-arm64"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `platform = on_arch_conditional arm: "darwin-arm64", intel: "darwin"` instead of `platform = Hardware::CPU.intel? ? "darwin": "darwin-arm64"`.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
        platform = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
      end
    CASK
  end
end
