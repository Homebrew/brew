# frozen_string_literal: true

require "rubocops/livecheck"

RSpec.describe RuboCop::Cop::FormulaAudit::LivecheckUrlProvided do
  subject(:cop) { described_class.new }

  it "reports an offense when a `url` is not specified in a `livecheck` block" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
        ^^^^^^^^^^^^ FormulaAudit/LivecheckUrlProvided: A `url` should be provided when `regex` or `strategy` are used.
          regex(%r{href=.*?/formula[._-]v?(\\d+(?:\\.\\d+)+)\\.t}i)
        end
      end
    RUBY

    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
        ^^^^^^^^^^^^ FormulaAudit/LivecheckUrlProvided: A `url` should be provided when `regex` or `strategy` are used.
          strategy :page_match
        end
      end
    RUBY
  end

  it "reports no offenses when a `url` and `regex` are specified in the `livecheck` block" do
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

  it "reports no offenses when a `url` and `strategy` are specified in the `livecheck` block" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url :stable
          strategy :page_match
        end
      end
    RUBY
  end
end
