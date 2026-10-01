# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::ConditionalArgumentsOrder, :config do
  it "reports no offenses when keys are in the canonical order" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: "-intel"
        file_arch = on_arch_conditional arm: "-aarch64", intel: "-x86_64"
        os macos: "-darwin", linux: "-linux"
        file_os = on_system_conditional macos: "-mac", linux: "-gnu"
      end
    CASK
  end

  it "reports no offenses when nested keys are in the canonical order" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(macos: "-intel", linux: "-x86_64")
        os macos: on_arch_conditional(arm: "-darwin", intel: "-mac"), linux: "-linux"
      end
    CASK
  end

  it "reports no offenses with single keys" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        arch arm: "-arm64"
        file_arch = on_arch_conditional intel: "-x86_64"
        os macos: "-darwin"
        file_os = on_system_conditional linux: "-gnu"
      end
    CASK
  end

  it "reports no offenses with single nested keys" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(macos: "-intel")
        os macos: on_arch_conditional(intel: "-mac"), linux: "-linux"
      end
    CASK
  end

  it "reports an offense when keys are in the wrong order" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch intel: "-intel", arm: "-arm64"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `arch` keys should be ordered: arm, intel
        file_arch = on_arch_conditional intel: "-x86_64", arm: "-aarch64"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `on_arch_conditional` keys should be ordered: arm, intel
        os linux: "-linux", macos: "-darwin"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `os` keys should be ordered: macos, linux
        file_os = on_system_conditional linux: "-gnu", macos: "-mac"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `on_system_conditional` keys should be ordered: macos, linux
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: "-intel"
        file_arch = on_arch_conditional arm: "-aarch64", intel: "-x86_64"
        os macos: "-darwin", linux: "-linux"
        file_os = on_system_conditional macos: "-mac", linux: "-gnu"
      end
    CASK
  end

  it "reports an offense when nested keys are in the wrong order" do
    expect_offense(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(linux: "-x86_64", macos: "-intel")
                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `on_system_conditional` keys should be ordered: macos, linux
        os macos: on_arch_conditional(intel: "-mac", arm: "-darwin"), linux: "-linux"
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `on_arch_conditional` keys should be ordered: arm, intel
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        arch arm: "-arm64", intel: on_system_conditional(macos: "-intel", linux: "-x86_64")
        os macos: on_arch_conditional(arm: "-darwin", intel: "-mac"), linux: "-linux"
      end
    CASK
  end
end
