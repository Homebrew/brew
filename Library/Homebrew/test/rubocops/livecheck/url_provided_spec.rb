# frozen_string_literal: true

require "rubocops/livecheck"

describe RuboCop::Cop::FormulaAudit::LivecheckUrlProvided do
  subject(:cop) { described_class.new }

  it "reports an offense when a `url` is not specified in the livecheck block" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
        ^^^^^^^^^^^^ FormulaAudit/LivecheckUrlProvided: A `url` must be provided to livecheck.
          regex(%r{href=.*?/formula[._-]v?(\\d+(?:\\.\\d+)+)\\.t}i)
        end
      end
    RUBY
  end

  it "reports no offenses when a `url` is specified in the livecheck block" do
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
