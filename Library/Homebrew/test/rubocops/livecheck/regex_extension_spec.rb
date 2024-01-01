# frozen_string_literal: true

require "rubocops/livecheck"

describe RuboCop::Cop::FormulaAudit::LivecheckRegexExtension do
  subject(:cop) { described_class.new }

  it "reports an offense when the `regex` does not use `\\.t` for archive file extensions" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url :stable
          regex(%r{href=.*?/formula[._-]v?(\\d+(?:\\.\\d+)+)\\.tgz}i)
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/LivecheckRegexExtension: Use `\\.t` instead of `\\.tgz`
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url :stable
          regex(%r{href=.*?/formula[._-]v?(\\d+(?:\\.\\d+)+)\\.t}i)
        end
      end
    RUBY
  end

  it "reports no offenses when the `regex` uses `\\.t` for archive file extensions" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url :stable
          regex(%r{href=.*?/formula[._-]v?(\\d+(?:\\.\\d+)+)\\.t}i)
        end
      end
    RUBY
  end
end
