# typed: strict
# frozen_string_literal: true

require "rubocops/no_multiline_interpolation"

RSpec.describe RuboCop::Cop::Homebrew::NoMultilineInterpolation, :config do
  it "flags a wrapped call inside an interpolation" do
    expect_offense(<<~'RUBY')
      "HTTP #{response.dig(:redirect,
            ^^ Keep each interpolation on one line.
                           :status)} #{reason}"
    RUBY
  end

  it "counts line breaks next to the interpolation delimiters" do
    expect_offense(<<~'RUBY')
      <<~TEXT
        #{
        ^^ Keep each interpolation on one line.
          status} #{reason
                  ^^ Keep each interpolation on one line.
        }
      TEXT
    RUBY
  end

  it "allows multiline strings with single-line interpolations and literal interpolation markers" do
    expect_no_offenses(<<~'RUBY')
      <<~TEXT
        #{status}
        #{reason}
      TEXT
      '#{
        literal}'
      (response.dig(:redirect,
                    :status))
    RUBY
  end
end
