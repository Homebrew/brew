# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::Sha256ArchOrder, :config do
  it "accepts keys in the canonical order" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        sha256 arm:          "arm",
               intel:        "intel",
               arm64_linux:  "arm64_linux",
               x86_64_linux: "x86_64_linux"
      end
    CASK
  end

  it "accepts a single checksum" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        sha256 "abc"
      end
    CASK
  end

  it "registers an offense and corrects Linux keys in the wrong order" do
    expect_offense(<<~CASK)
      cask "foo" do
        sha256 x86_64_linux: "x86_64_linux",
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `sha256` architecture keys should be ordered: arm, intel (or x86_64), arm64_linux, x86_64_linux
               arm64_linux:  "arm64_linux"
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        sha256 arm64_linux:  "arm64_linux",
               x86_64_linux: "x86_64_linux"
      end
    CASK
  end

  it "registers an offense and corrects macOS keys listed after Linux keys" do
    expect_offense(<<~CASK)
      cask "foo" do
        sha256 x86_64_linux: "x86_64_linux",
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `sha256` architecture keys should be ordered: arm, intel (or x86_64), arm64_linux, x86_64_linux
               arm:          "arm"
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        sha256 arm:          "arm",
               x86_64_linux: "x86_64_linux"
      end
    CASK
  end

  it "registers offenses and corrects within `on_macos` and `on_linux` blocks" do
    expect_offense(<<~CASK)
      cask "foo" do
        on_macos do
          sha256 intel: "intel",
          ^^^^^^^^^^^^^^^^^^^^^^ `sha256` architecture keys should be ordered: arm, intel (or x86_64), arm64_linux, x86_64_linux
                 arm:   "arm"
        end

        on_linux do
          sha256 x86_64_linux: "x86_64_linux",
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `sha256` architecture keys should be ordered: arm, intel (or x86_64), arm64_linux, x86_64_linux
                 arm64_linux:  "arm64_linux"
        end
      end
    CASK

    expect_correction(<<~CASK)
      cask "foo" do
        on_macos do
          sha256 arm:   "arm",
                 intel: "intel"
        end

        on_linux do
          sha256 arm64_linux:  "arm64_linux",
                 x86_64_linux: "x86_64_linux"
        end
      end
    CASK
  end
end
