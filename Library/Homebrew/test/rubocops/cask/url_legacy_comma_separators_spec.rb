# frozen_string_literal: true

require "rubocops/rubocop-cask"

RSpec.describe RuboCop::Cop::Cask::UrlLegacyCommaSeparators, :config do
  it "accepts a simple `version` interpolation" do
    expect_no_offenses <<~'CASK'
      cask 'foo' do
        version '1.1'
        url 'https://foo.brew.sh/foo-#{version}.dmg'
      end
    CASK
  end

  it "accepts an interpolation using `version.csv`" do
    expect_no_offenses <<~'CASK'
      cask 'foo' do
        version '1.1,111'
        url 'https://foo.brew.sh/foo-#{version.csv.first}.dmg'
      end
    CASK
  end

  it "reports an offense for an interpolation using `version.before_comma`" do
    expect_offense <<~'CASK'
      cask 'foo' do
        version '1.1,111'
        url 'https://foo.brew.sh/foo-#{version.before_comma}.dmg'
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `version.csv.first` instead of `version.before_comma` and `version.csv.second` instead of `version.after_comma`.
      end
    CASK

    expect_correction <<~'CASK'
      cask 'foo' do
        version '1.1,111'
        url 'https://foo.brew.sh/foo-#{version.csv.first}.dmg'
      end
    CASK
  end

  it "reports an offense for an interpolation using `version.after_comma`" do
    expect_offense <<~'CASK'
      cask 'foo' do
        version '1.1,111'
        url 'https://foo.brew.sh/foo-#{version.after_comma}.dmg'
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `version.csv.first` instead of `version.before_comma` and `version.csv.second` instead of `version.after_comma`.
      end
    CASK

    expect_correction <<~'CASK'
      cask 'foo' do
        version '1.1,111'
        url 'https://foo.brew.sh/foo-#{version.csv.second}.dmg'
      end
    CASK
  end
end
