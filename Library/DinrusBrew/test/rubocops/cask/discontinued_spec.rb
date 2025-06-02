# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::Discontinued, :config do
  it "reports no offenses when there is no `caveats` stanza" do
    expect_no_offenses <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"
      end
    CASK
  end

  it "reports no offenses when there is a `caveats` stanza without `discontinued`" do
    expect_no_offenses <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"

        caveats do
          files_in_usr_local
        end
      end
    CASK
  end

  it "reports an offense when there is a `caveats` stanza with `discontinued` and other caveats" do
    expect_offense <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"

        caveats do
          discontinued
          ^^^^^^^^^^^^ Use `deprecate!` instead of `caveats { discontinued }`.
          files_in_usr_local
        end
      end
    CASK
  end

  it "corrects `caveats { discontinued }` to `deprecate!`" do
    expect_offense <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"

        caveats do
        ^^^^^^^^^^ Use `deprecate!` instead of `caveats { discontinued }`.
          discontinued
        end
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        url "https://example.com/download/foo-v1.2.0.dmg",
            verified: "example.com/download/"

        deprecate! date: "#{Date.today}", because: :discontinued
      end
    CASK
  end
end
