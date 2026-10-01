# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::UninstallWildcard, :config do
  it "reports an offense when a quit bundle ID is only a wildcard" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall quit: "*"
                        ^^^ Include at least 3 parts of an ID with a wildcard, e.g. `com.example.*`.
      end
    CASK
  end

  it "reports an offense when a wildcard has too little of an ID to match on" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall quit: "com.a*"
                        ^^^^^^^^ Include at least 3 parts of an ID with a wildcard, e.g. `com.example.*`.
      end
    CASK
  end

  it "reports an offense when a signal bundle ID has nothing to match on" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall signal: [
          ["TERM", "*.*.*"],
                   ^^^^^^^ Include at least 3 parts of an ID with a wildcard, e.g. `com.example.*`.
        ]
      end
    CASK
  end

  it "reports an offense for a launchctl ID in a zap stanza" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap launchctl: ["com.example.foo", "c*.a*"]
                                           ^^^^^^^ Include at least 3 parts of an ID with a wildcard, e.g. `com.example.*`.
      end
    CASK
  end

  it "reports no offenses when a wildcard includes enough of an ID" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall quit:      "com.hp.scan.*",
                  launchctl: "*.com.example.foo.*",
                  signal:    [["TERM", "com.example.foo*"]]
      end
    CASK
  end

  it "reports no offenses for an interpolated ID" do
    expect_no_offenses(<<~'CASK')
      cask "foo" do
        version "1.0"
        url "https://example.com/foo.zip"

        uninstall quit: "com.example.foo.#{version.major}*"
      end
    CASK
  end

  it "reports no offenses without a wildcard" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall quit: "com.example.foo"
      end
    CASK
  end

  it "reports no offenses for a wildcard in a path directive" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap trash: "~/Library/Application Support/com.example.foo/*"
      end
    CASK
  end
end
