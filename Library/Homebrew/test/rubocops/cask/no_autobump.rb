# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::NoAutobump, :config do
  it "reports no offenses if `reason` is acceptable" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        no_autobump! because: "some reason"
      end
    CASK
  end

  it "reports no offenses if `reason` is acceptable as a symbol" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        no_autobump! because: :bumped_by_upstream
      end
    CASK
  end

  it "reports an offense if `reason` is absent" do
    expect_offense <<~CASK
      cask 'foo' do
        no_autobump!
        ^^^^^^^^^^^ Add a reason for exclusion from autobump: `no_autobump! because: "..."`
      end
    CASK
  end

  it "reports an offense is `reason` should not be set manually" do
    expect_offense <<~CASK
      cask 'foo' do
        no_autobump! because: :extract_plist
                              ^^^^^^^^^^^^^^ `:extract_plist` reason should not be used directly
      end
    CASK
  end

  it "reports and corrects an offense if `reason` starts with 'it'" do
    expect_offense <<~CASK
      cask 'foo' do
        no_autobump! because: "it does something"
                              ^^^^^^^^^^^^^^^^^^^ Do not start the reason with `it`
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        no_autobump! because: "does something"
      end
    CASK
  end

  it "reports and corrects an offense if `reason` ends with a period" do
    expect_offense <<~CASK
      cask 'foo' do
        no_autobump! because: "does something."
                              ^^^^^^^^^^^^^^^^^ Do not end the reason with a punctuation mark
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        no_autobump! because: "does something"
      end
    CASK
  end

  it "reports and corrects an offense if `reason` ends with an exclamation point" do
    expect_offense <<~CASK
      cask 'foo' do
        no_autobump! because: "does something!"
                              ^^^^^^^^^^^^^^^^^ Do not end the reason with a punctuation mark
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        no_autobump! because: "does something"
      end
    CASK
  end

  it "reports and corrects an offense if `reason` ends with a question mark" do
    expect_offense <<~CASK
      cask 'foo' do
        no_autobump! because: "does something?"
                              ^^^^^^^^^^^^^^^^^ Do not end the reason with a punctuation mark
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        no_autobump! because: "does something"
      end
    CASK
  end
end
