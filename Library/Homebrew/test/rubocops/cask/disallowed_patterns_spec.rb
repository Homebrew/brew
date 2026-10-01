# typed: strict
# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::DisallowedPatterns, :config do
  it "reports an offense when a quit ID is only the install4j prefix and a wildcard" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall quit: "com.install4j.*"
                        ^^^^^^^^^^^^^^^^^ install4j distributions must include the unique ID number, e.g. `com.install4j.1234-5678-9012-3456`, to prevent matching other applications.
      end
    CASK

    expect_no_corrections
  end

  it "reports an offense for a disallowed pattern in a zap stanza" do
    expect_offense(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        zap launchctl: ["com.example.foo", "com.install4j.*"],
                                           ^^^^^^^^^^^^^^^^^ install4j distributions must include the unique ID number, e.g. `com.install4j.1234-5678-9012-3456`, to prevent matching other applications.
            trash:     "~/Library/Preferences/com.install4j.*.plist"
                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ install4j distributions must include the unique ID number, e.g. `com.install4j.1234-5678-9012-3456`, to prevent matching other applications.
      end
    CASK
  end

  it "reports no offenses when the wildcard follows a whole ID" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall quit:      "com.install4j.1234-5678-9012-3456*",
                  launchctl: "com.install4j.1234-5678-9012-3456.*"

        zap trash: "~/Library/Saved Application State/com.install4j.1234-5678-9012-3456.*.savedState"
      end
    CASK
  end

  it "reports no offenses without a disallowed pattern" do
    expect_no_offenses(<<~CASK)
      cask "foo" do
        url "https://example.com/foo.zip"

        uninstall quit: "com.install4j.1234-5678-9012-3456.22"

        zap trash: "~/Library/Preferences/com.install4j.installations.plist"
      end
    CASK
  end
end
