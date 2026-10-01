# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::Url, :config do
  it "allows regular `url` blocks in homebrew-cask" do
    expect_no_offenses <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg"
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
        url "https://example.com/download/foo-v1.2.0.dmg"
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

  it "reports an offense for a keyword parameter on the same line as the URL" do
    expect_offense <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg", header: "Accept: application/octet-stream"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Keyword URL parameter should be on a new indented line.
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            header: "Accept: application/octet-stream"
      end
    CASK
  end

  it "reports an offense for a `url` stanza with only keyword arguments" do
    expect_offense <<~CASK
      cask "foo" do
        url header: "Accept"
        ^^^^^^^^^^^^^^^^^^^^ The `url` stanza requires a URL argument.
      end
    CASK
  end

  it "accepts a method call URL with a keyword parameter on a new indented line" do
    expect_no_offenses <<~CASK
      cask "foo" do
        version "1.2.0"
        url Utils.download_url(version),
            header: "Accept: application/octet-stream"
      end
    CASK
  end

  it "reports an offense for a method call URL with a keyword parameter on the same line" do
    expect_offense <<~CASK
      cask "foo" do
        version "1.2.0"
        url Utils.download_url(version), header: "Accept: application/octet-stream"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Keyword URL parameter should be on a new indented line.
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        version "1.2.0"
        url Utils.download_url(version),
            header: "Accept: application/octet-stream"
      end
    CASK
  end

  it "accepts multiple keyword parameters each on their own line" do
    expect_no_offenses <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            header: "Accept: application/octet-stream",
            user_agent: :fake
      end
    CASK
  end

  it "reports an offense for a keyword parameter on the same line as another keyword parameter" do
    expect_offense <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            header: "Accept: application/octet-stream", user_agent: :fake
                                                        ^^^^^^^^^^^^^^^^^ Keyword URL parameter should be on a new indented line.
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            header: "Accept: application/octet-stream",
            user_agent: :fake
      end
    CASK
  end

  it "reports an offense for a keyword splat on the same line as another keyword parameter" do
    expect_offense <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            header: "Accept: application/octet-stream", **options
                                                        ^^^^^^^^^ Keyword URL parameter should be on a new indented line.
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            header: "Accept: application/octet-stream",
            **options
      end
    CASK
  end

  it "reports an offense for a keyword parameter on the last line of a multiline keyword parameter" do
    expect_offense <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            data: {
              key: "value",
            }, user_agent: :fake
               ^^^^^^^^^^^^^^^^^ Keyword URL parameter should be on a new indented line.
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            data: {
              key: "value",
            },
            user_agent: :fake
      end
    CASK
  end

  it "reports an offense for an http:// URL in homebrew-cask" do
    expect_offense <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        url "http://example.com/download/foo-v1.2.0.dmg"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Casks in homebrew/cask should not use http:// URLs
      end
    CASK
  end

  it "autocorrects http:// to https:// in homebrew-cask" do
    expect_offense <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        url "http://example.com/download/foo-v1.2.0.dmg"
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Casks in homebrew/cask should not use http:// URLs
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg"
      end
    CASK
  end

  it "reports no offense for http:// URL outside homebrew-cask" do
    expect_no_offenses <<~CASK, "/homebrew-mytap/Casks/f/foo.rb"
      cask "foo" do
        url "http://example.com/download/foo-v1.2.0.dmg"
      end
    CASK
  end

  it "reports an offense for a non-string-literal URL in homebrew-cask" do
    expect_offense <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        version "1.2.3"
        url Utils.download_url(version)
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Casks in homebrew/cask should use string literal URLs.
      end
    CASK
  end

  it "accepts an interpolated string URL in homebrew-cask" do
    expect_no_offenses <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        version "1.2.3"
        url "https://example.com/download/foo-v\#{version}.dmg"
      end
    CASK
  end

  it "accepts a non-string-literal URL outside homebrew-cask" do
    expect_no_offenses <<~CASK, "/homebrew-tap/Casks/f/foo.rb"
      cask "foo" do
        version "1.2.3"
        url Utils.download_url(version)
      end
    CASK
  end

  it "reports no offense for an https:// URL" do
    expect_no_offenses <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg"
      end
    CASK
  end

  it "reports no offense for deprecated casks" do
    expect_no_offenses <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        url "http://example.com/download/foo-v1.2.0.dmg"
        deprecate! date: "2024-01-01", because: :unmaintained
      end
    CASK
  end

  it "reports no offense for disabled casks" do
    expect_no_offenses <<~CASK, "/homebrew-cask/Casks/f/foo.rb"
      cask "foo" do
        url "http://example.com/download/foo-v1.2.0.dmg"
        disable! date: "2024-01-01", because: :unmaintained
      end
    CASK
  end
end
