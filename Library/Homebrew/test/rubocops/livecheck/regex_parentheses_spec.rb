# frozen_string_literal: true

require "rubocops/livecheck"

RSpec.describe RuboCop::Cop::FormulaAudit::LivecheckRegexParentheses do
  subject(:cop) { described_class.new }

  it "reports an offense when the `regex` call in the `livecheck` block does not use parentheses" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url :stable
          regex %r{href=.*?/formula[._-]v?(\\d+(?:\\.\\d+)+)\\.t}i
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/LivecheckRegexParentheses: The `regex` call should always use parentheses.
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

  it "reports no offenses when the `regex` call in the `livecheck` block uses parentheses" do
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
