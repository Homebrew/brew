# typed: strict
# frozen_string_literal: true

require "rubocops/simple_interpolation"

RSpec.describe RuboCop::Cop::Homebrew::SimpleInterpolation, :config do
  it "checks each interpolation independently" do
    expect_offense(<<~'RUBY')
      "#{queue.name.to_s.strip.size} #{data.dig(:a, :b)} #{queue.name.to_s.strip}"
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside the interpolation.
      "#{ready? ? queue : fallback}"
       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Move this expression outside the interpolation.
      "#{prepare; queue}"
       ^^^^^^^^^^^^^^^^^ Move this expression outside the interpolation.
    RUBY
  end

  it "checks interpolation in symbols, regular expressions, commands and heredocs" do
    expect_offense(<<~'RUBY')
      :"queue-#{size + 1}"
              ^^^^^^^^^^^ Move this expression outside the interpolation.
      /queue-#{size + 1}/
             ^^^^^^^^^^^ Move this expression outside the interpolation.
      %x(echo #{size + 1})
              ^^^^^^^^^^^ Move this expression outside the interpolation.
      <<~TEXT
        queue-#{size + 1}
              ^^^^^^^^^^^ Move this expression outside the interpolation.
      TEXT
    RUBY
  end

  it "ignores empty interpolation, literal text and expressions outside interpolation" do
    expect_no_offenses(<<~'RUBY')
      "#{} #@queue"
      '#{queue || fallback}'
      (queue || fallback)
    RUBY
  end
end
