# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::NoNestedOSDependency, :config do
  it "reports bare operating-system dependencies inside OS blocks" do
    expect_offense <<~CASK
      cask "foo" do
        on_macos do
          depends_on(:macos)
          ^^^^^^^^^^^^^^^^^^ A bare macOS dependency must not be nested in this conditional block. Move it to the top level if the cask is macOS-only; otherwise remove it.
        end
        on_linux do
          depends_on linux: :any
          ^^^^^^^^^^^^^^^^^^^^^^ A bare Linux dependency must not be nested in this conditional block. Move it to the top level if the cask is Linux-only; otherwise remove it.
        end
        on_ventura :or_newer do
          depends_on macos: :any
          ^^^^^^^^^^^^^^^^^^^^^^ A bare macOS dependency must not be nested in this conditional block. Move it to the top level if the cask is macOS-only; otherwise remove it.
        end
        on_system :linux, macos: :big_sur do
          depends_on :linux
          ^^^^^^^^^^^^^^^^^ A bare Linux dependency must not be nested in this conditional block. Move it to the top level if the cask is Linux-only; otherwise remove it.
        end
      end
    CASK

    expect_no_corrections
  end

  it "reports dependencies inside architecture blocks nested in OS blocks" do
    expect_offense <<~CASK
      cask "foo" do
        on_macos do
          on_arm do
            depends_on :macos
            ^^^^^^^^^^^^^^^^^ A bare macOS dependency must not be nested in this conditional block. Move it to the top level if the cask is macOS-only; otherwise remove it.
          end
        end
      end
      cask "bar" do
        on_arm do
          on_macos do
            depends_on :macos
            ^^^^^^^^^^^^^^^^^ A bare macOS dependency must not be nested in this conditional block. Move it to the top level if the cask is macOS-only; otherwise remove it.
          end
        end
      end
    CASK
  end

  it "reports Linux dependencies inside architecture-only blocks" do
    expect_offense <<~CASK
      cask "foo" do
        on_arm do
          depends_on :linux
          ^^^^^^^^^^^^^^^^^ A bare Linux dependency must not be nested in this conditional block. Move it to the top level if the cask is Linux-only; otherwise remove it.
        end
        on_intel do
          depends_on linux: :any
          ^^^^^^^^^^^^^^^^^^^^^^ A bare Linux dependency must not be nested in this conditional block. Move it to the top level if the cask is Linux-only; otherwise remove it.
        end
      end
    CASK
  end

  it "accepts macOS dependencies inside architecture-only blocks" do
    expect_no_offenses <<~CASK
      cask "foo" do
        on_arm do
          depends_on macos: :any
        end
        on_intel do
          depends_on :macos
        end
      end
    CASK
  end

  it "accepts top-level and versioned operating-system dependencies" do
    expect_no_offenses <<~CASK
      cask "foo-macos" do
        depends_on :macos
      end
      cask "foo-versioned-macos" do
        depends_on macos: :ventura
      end
      cask "foo-linux" do
        depends_on linux: :any
      end
    CASK
  end

  it "accepts unrelated dependencies and calls with a receiver inside OS blocks" do
    expect_no_offenses <<~CASK
      cask "foo" do
        on_macos do
          depends_on cask: "other"
          other.depends_on :macos
        end
      end
    CASK
  end

  it "accepts operating-system dependencies outside cask blocks" do
    expect_no_offenses <<~RUBY
      class Foo < Formula
        on_macos do
          depends_on :macos
        end
      end
    RUBY
  end
end
