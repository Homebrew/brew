# typed: strict
# frozen_string_literal: true

require "rubocops/api_name_membership"

RSpec.describe RuboCop::Cop::Homebrew::ApiNameMembership, :config do
  it "registers an offense and corrects when scanning `formula_names` with `include?`" do
    expect_offense(<<~RUBY)
      Homebrew::API.formula_names.include?(name)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Homebrew::API.formula_name?` instead of scanning `Homebrew::API.formula_names`.
    RUBY

    expect_correction(<<~RUBY)
      Homebrew::API.formula_name?(name)
    RUBY
  end

  it "registers an offense and corrects when scanning `cask_tokens` with `exclude?`" do
    expect_offense(<<~RUBY)
      Homebrew::API.cask_tokens.exclude?(token)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `Homebrew::API.cask_token?` instead of scanning `Homebrew::API.cask_tokens`.
    RUBY

    expect_correction(<<~RUBY)
      !Homebrew::API.cask_token?(token)
    RUBY
  end

  it "does not register an offense for membership checks on other receivers" do
    expect_no_offenses(<<~RUBY)
      tap.formula_names.include?(name)
      formula_names.include?(name)
      Homebrew::API.formula_aliases.exclude?(name)
    RUBY
  end
end
