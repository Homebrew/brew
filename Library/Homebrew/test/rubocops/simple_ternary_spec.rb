# typed: strict
# frozen_string_literal: true

require "rubocops/simple_ternary"

RSpec.describe RuboCop::Cop::Homebrew::SimpleTernary, :config do
  it "checks the condition and both branches independently" do
    expect_offense(<<~RUBY)
      enabled && ready? ? queue.name.to_s.strip.size : size + 1
      ^^^^^^^^^^^^^^^^^ Use `if`/`else` for this complex ternary.
                          ^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `if`/`else` for this complex ternary.
                                                       ^^^^^^^^ Use `if`/`else` for this complex ternary.
      queue.ready? ? data.dig(:a, :b) : queue.name.to_s.strip
    RUBY
  end

  it "ignores ordinary conditionals" do
    expect_no_offenses(<<~RUBY)
      if enabled && ready?
        size + 1
      else
        size - 1
      end
      size + 1 unless enabled && ready?
    RUBY
  end
end
