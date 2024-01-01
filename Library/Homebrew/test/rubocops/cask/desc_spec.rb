# frozen_string_literal: true

require "rubocops/rubocop-cask"

describe RuboCop::Cop::Cask::Desc, :config do
  it "does not start with an article" do
    expect_no_offenses <<~RUBY
      cask "foo" do
        desc "Bar program"
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo' do
        desc 'A bar program'
              ^ Description shouldn't start with an article.
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo' do
        desc 'The bar program'
              ^^^ Description shouldn't start with an article.
      end
    RUBY

    expect_correction <<~RUBY
      cask 'foo' do
        desc 'Bar program'
      end
    RUBY
  end

  it "does not start with the cask name" do
    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foobar' do
        desc 'Foo bar program'
              ^^^^^^^ Description shouldn't start with the cask name.
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foobar' do
        desc 'Foo-Bar program'
              ^^^^^^^ Description shouldn't start with the cask name.
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo-bar' do
        desc 'Foo bar program'
              ^^^^^^^ Description shouldn't start with the cask name.
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo-bar' do
        desc 'Foo-Bar program'
              ^^^^^^^ Description shouldn't start with the cask name.
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo-bar' do
        desc 'Foo Bar'
              ^^^^^^^ Description shouldn't start with the cask name.
      end
    RUBY
  end

  it "does not contain the platform" do
    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo-bar' do
        desc 'macOS status bar monitor'
              ^^^^^ Description shouldn't contain the platform.
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo-bar' do
        desc 'Toggles dark mode on Mac OS Mojave'
                                   ^^^^^^ Description shouldn't contain the platform.
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo-bar' do
        desc 'Better input source switcher for OS X'
                                               ^^^^ Description shouldn't contain the platform.
      end
    RUBY

    expect_offense <<~RUBY, "/homebrew-cask/Casks/foo.rb"
      cask 'foo-bar' do
        desc 'Media Manager for Mac OS X'
                                ^^^^^^^^ Description shouldn't contain the platform.
      end
    RUBY

    expect_no_offenses <<~RUBY
      cask 'foo' do
        desc 'Application for managing macOS virtual machines'
      end
    RUBY

    expect_offense <<~RUBY
      cask 'foo' do
        desc 'Application for managing macOS virtual machines on macOS'
                                                                 ^^^^^ Description shouldn't contain the platform.
      end
    RUBY

    expect_offense <<~RUBY
      cask 'foo' do
        desc 'Description with a 🍺 symbol'
                                 ^ Description shouldn't contain Unicode emojis or symbols.
      end
    RUBY

    expect_no_offenses <<~RUBY
      cask 'foo' do
        desc 'MAC address changer'
      end
    RUBY
  end
end
