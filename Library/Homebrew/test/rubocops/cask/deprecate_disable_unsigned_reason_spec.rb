# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::DeprecateDisableUnsignedReason, :config do
  it "flags and autocorrects deprecate! with :unsigned" do
    expect_offense <<~CASK
      cask "foo" do
        deprecate! date: "2024-01-01", because: :unsigned
                                                ^^^^^^^^^ Use `:fails_gatekeeper_check` instead of `:unsigned` for deprecate!/disable! reason.
      end
    CASK

    expect_correction <<~CASK
      cask "foo" do
        deprecate! date: "2024-01-01", because: :fails_gatekeeper_check
      end
    CASK
  end

  it "flags and autocorrects disable! with :unsigned" do
    expect_offense <<~CASK
      cask "bar" do
        disable! because: :unsigned
                          ^^^^^^^^^ Use `:fails_gatekeeper_check` instead of `:unsigned` for deprecate!/disable! reason.
      end
    CASK

    expect_correction <<~CASK
      cask "bar" do
        disable! because: :fails_gatekeeper_check
      end
    CASK
  end

  it "ignores other reasons" do
    expect_no_offenses <<~CASK
      cask "baz" do
        deprecate! date: "2024-01-01", because: :discontinued
        disable! because: :no_longer_available
      end
    CASK
  end
end
