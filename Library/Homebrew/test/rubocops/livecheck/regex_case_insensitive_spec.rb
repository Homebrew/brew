# frozen_string_literal: true

require "rubocops/livecheck"

RSpec.describe RuboCop::Cop::FormulaAudit::LivecheckRegexCaseInsensitive do
  subject(:cop) { described_class.new }

  it "reports an offense when the `regex` is not case-insensitive" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url :stable
          regex(%r{href=.*?/formula[._-]v?(\\d+(?:\\.\\d+)+)\\.t})
                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/LivecheckRegexCaseInsensitive: Regexes should be case-insensitive unless sensitivity is explicitly required for proper matching.
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

  it "reports no offenses when the `regex` is case-insensitive" do
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
