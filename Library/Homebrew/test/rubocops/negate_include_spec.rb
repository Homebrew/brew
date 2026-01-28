# frozen_string_literal: true

require "rubocops/negate_include"

RSpec.describe RuboCop::Cop::Homebrew::NegateInclude, :config do
  it "registers an offense and corrects when using `!include?`" do
    expect_offense(<<~RUBY)
      !array.include?(2)
      ^^^^^^^^^^^^^^^^^^ Use `.exclude?` and remove the negation part.
    RUBY

    expect_correction(<<~RUBY)
      array.exclude?(2)
    RUBY
  end

  it "does not register an offense when using `!include?` without receiver" do
    expect_no_offenses(<<~RUBY)
      !include?(2)
    RUBY
  end

  it "does not register an offense when using `include?` or `exclude?`" do
    expect_no_offenses(<<~RUBY)
      array.include?(2)
      array.exclude?(2)
    RUBY
  end
end
