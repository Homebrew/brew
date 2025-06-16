# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::Url, :config do
  it "allows regular `url` blocks in homebrew-cask" do
    expect_no_offenses <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"
      end
    CASK
  end

  it "does not allow `url do` blocks in homebrew-cask" do
    expect_offense <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg" do |url|
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Do not use `url "..." do` blocks in Homebrew/homebrew-cask.
          url
        end
      end
    CASK
  end

  it "allows regular `url` blocks in a non-homebrew-cask tap" do
    expect_no_offenses <<~CASK, "/homebrew-tap/Casks/f/foo.rb"
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"
      end
    CASK
  end

  it "allows `url do` blocks in a non-homebrew-cask tap" do
    expect_no_offenses <<~CASK, "/homebrew-tap/Casks/f/foo.rb"
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg" do |url|
          url
        end
      end
    CASK
  end

  it "accepts a `verified` value that does not start with a protocol" do
    expect_no_offenses <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"
      end
    CASK
  end

  it "reports an offense for a `verified` value that starts with a protocol" do
    expect_offense <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "https://example.com/download/"
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Verified URL parameter value should not contain a URL scheme.
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"
      end
    CASK
  end

  context "when then URL does not have a path and ends with a /" do
    it "accepts a `verified` value ending with a /" do
      expect_no_offenses <<~CASK
        cask "foo" do
          url "https://example.org/",
              verified: "example.org/"
        end
      CASK
    end

    it "reports an offense for a `verified` value not ending a /" do
      expect_offense <<~CASK
        cask "foo" do
          url "https://example.org/",
              verified: "example.org"
                        ^^^^^^^^^^^^^ Verified URL parameter value should end with a /.
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          url "https://example.org/",
              verified: "example.org/"
        end
      CASK
    end
  end

  context "when the URL has a path and does not end with a /" do
    it "accepts a `verified` value with one path component" do
      expect_no_offenses <<~CASK
        cask "foo" do
          url "https://github.com/Foo",
              verified: "github.com/Foo"
        end
      CASK
    end

    it "accepts a `verified` value with two path components" do
      expect_no_offenses <<~CASK
        cask "foo" do
          url "https://github.com/foo/foo.git",
              verified: "github.com/foo/foo"
        end
      CASK
    end
  end

  context "when the url ends with a /" do
    it "accepts a `verified` value ending with a /" do
      expect_no_offenses <<~CASK
        cask "foo" do
          url "https://github.com/",
              verified: "github.com/"
        end
      CASK
    end

    it "reports an offense for a `verified` value not ending with a /" do
      expect_offense <<~CASK
        cask "foo" do
          url "https://github.com/",
              verified: "github.com"
                        ^^^^^^^^^^^^ Verified URL parameter value should end with a /.
        end
      CASK

      expect_correction <<~CASK
        cask "foo" do
          url "https://github.com/",
              verified: "github.com/"
        end
      CASK
    end
  end

  it "accepts a `verified` value with a path ending with a /" do
    expect_no_offenses <<~CASK
      cask "foo" do
        url "https://github.com/Foo/foo/releases/download/v1.2.0/foo-v1.2.0.dmg",
            verified: "github.com/Foo/foo/"
      end
    CASK
  end

  context "when the URL uses interpolation" do
    it "accepts a `verified` value with a path ending with a /" do
      expect_no_offenses <<~CASK
        cask "foo" do
          version "1.2.3"
          url "Cask/Url: https://example.com/download/foo-v\#{version}.dmg",
              verified: "example.com/download/"
        end
      CASK
    end
  end

  it "reports an offense for a `verified` value with a path component that doesn't end with a /" do
    expect_offense <<~CASK
      cask "foo" do
        url "https://github.com/Foo/foo/releases/download/v1.2.0/foo-v1.2.0.dmg",
            verified: "github.com/Foo/foo"
                      ^^^^^^^^^^^^^^^^^^^^ Verified URL parameter value should end with a /.
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        url "https://github.com/Foo/foo/releases/download/v1.2.0/foo-v1.2.0.dmg",
            verified: "github.com/Foo/foo/"
      end
    CASK
  end
end
