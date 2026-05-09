# typed: false
# frozen_string_literal: true

require "rubocops/full_name_split"

RSpec.describe RuboCop::Cop::Homebrew::FullNameSplit, :config do
  it "registers and corrects an offense when using `name.split(\"/\").last`" do
    expect_offense(<<~RUBY)
      name.split("/").last
      ^^^^^^^^^^^^^^^^^^^^ Use `Utils.name_from_full_name` instead of splitting formula or cask full names.
    RUBY

    expect_correction(<<~RUBY)
      ::Utils.name_from_full_name(name)
    RUBY
  end

  it "registers and corrects an offense when using `token.split(\"/\").fetch(-1)`" do
    expect_offense(<<~RUBY)
      token.split("/").fetch(-1)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Utils.name_from_full_name` instead of splitting formula or cask full names.
    RUBY

    expect_correction(<<~RUBY)
      ::Utils.name_from_full_name(token)
    RUBY
  end

  it "registers and corrects an offense when using a safe navigation split" do
    expect_offense(<<~RUBY)
      dep["full_name"]&.split("/")&.last
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Utils.name_from_full_name` instead of splitting formula or cask full names.
    RUBY

    expect_correction(<<~RUBY)
      dep["full_name"]&.then { ::Utils.name_from_full_name(it) }
    RUBY
  end

  it "registers and corrects an offense for known full-name variables" do
    expect_offense(<<~RUBY)
      dep_name.split("/").last
      ^^^^^^^^^^^^^^^^^^^^^^^^ Use `Utils.name_from_full_name` instead of splitting formula or cask full names.
      full_name.split("/").last
      ^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Utils.name_from_full_name` instead of splitting formula or cask full names.
    RUBY

    expect_correction(<<~RUBY)
      ::Utils.name_from_full_name(dep_name)
      ::Utils.name_from_full_name(full_name)
    RUBY
  end

  it "does not register an offense for URL or path component parsing" do
    expect_no_offenses(<<~RUBY)
      url.split("/").last
      line.split("/").fetch(-1)
      file_name.split("/").last
    RUBY
  end

  it "does not register an offense for two-part tap full names" do
    expect_no_offenses(<<~RUBY)
      user, repo = tap.full_name.split("/")
      tap.full_name.split("/").last
      formula.tap.full_name.split("/").last
      tap_name.split("/").last
    RUBY
  end

  it "does not register an offense for mixed safe navigation" do
    expect_no_offenses(<<~RUBY)
      name&.split("/").last
      name.split("/")&.last
    RUBY
  end
end
