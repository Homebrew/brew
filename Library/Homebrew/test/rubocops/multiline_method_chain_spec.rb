# typed: strict
# frozen_string_literal: true

require "rubocops/multiline_method_chain"

RSpec.describe RuboCop::Cop::Homebrew::MultilineMethodChain, :config do
  it "corrects calls sharing the first line of a split chain" do
    expect_offense(<<~RUBY)
      dependents(formulae, installed).keys.to_set
                                          ^ Keep one dotted call per line in a multiline chain.
                                     .merge(formulae.flat_map(&:names))
    RUBY

    expect_correction(<<~RUBY)
      dependents(formulae, installed).keys
                                     .to_set
                                     .merge(formulae.flat_map(&:names))
    RUBY
  end

  it "corrects calls sharing a continuation line across a block and safe navigation" do
    expect_offense(<<~RUBY)
      values
        &.map { |value| value.name.strip }&.compact.sort
                                          ^^ Keep one dotted call per line in a multiline chain.
                                                   ^ Keep one dotted call per line in a multiline chain.
    RUBY

    expect_correction(<<~RUBY)
      values
        &.map { |value| value.name.strip }
        &.compact
        .sort
    RUBY
  end

  it "accepts a chain on one line" do
    expect_no_offenses("dependents(formulae, installed).keys.to_set.merge(other)")
  end

  it "accepts one call per line" do
    expect_no_offenses(<<~RUBY)
      dependents(formulae, installed).keys
                                     .to_set
                                     .merge(other)
    RUBY
  end

  it "allows line breaks inside arguments" do
    expect_no_offenses(<<~RUBY)
      values.fetch(
        key,
      ).keys.to_set
    RUBY
  end

  it "keeps calls on the opening line of a heredoc" do
    expect_no_offenses(<<~RUBY)
      parse(<<~TEXT).keys.to_set
        example
      TEXT
                    .merge(other)
    RUBY
  end

  it "keeps the first call on the closing line of a block" do
    expect_offense(<<~RUBY)
      values
        .map do |value|
          value.name
        end.join.chomp
                ^ Keep one dotted call per line in a multiline chain.
    RUBY

    expect_correction(<<~RUBY)
      values
        .map do |value|
          value.name
        end.join
        .chomp
    RUBY
  end

  it "accepts a single call on the closing line of an argument list" do
    expect_no_offenses(<<~RUBY)
      values
        .fetch(
          key,
        ).to_set
    RUBY
  end
end
