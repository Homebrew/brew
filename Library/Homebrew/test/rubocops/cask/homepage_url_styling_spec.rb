# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::HomepageUrlStyling, :config do
  it "accepts a homepage URL ending with a slash" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh/'
      end
    CASK
  end

  it "accepts a homepage URL with a path" do
    expect_no_offenses <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh/path'
      end
    CASK
  end

  it "reports an offense when the homepage URL does not end with a slash and has no path" do
    expect_offense <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh'
                 ^^^^^^^^^^^^^^^^^^^^^ 'https://foo.brew.sh' must have a slash after the domain.
      end
    CASK

    expect_correction <<~CASK
      cask 'foo' do
        homepage 'https://foo.brew.sh/'
      end
    CASK
  end
end
