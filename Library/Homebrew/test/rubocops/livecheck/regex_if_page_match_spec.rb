# frozen_string_literal: true

require "rubocops/livecheck"

RSpec.describe RuboCop::Cop::FormulaAudit::LivecheckRegexIfPageMatch do
  subject(:cop) { described_class.new }

  it "reports an offense when there is no `regex` for `strategy :page_match`" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
        ^^^^^^^^^^^^ FormulaAudit/LivecheckRegexIfPageMatch: A `regex` is required if `strategy :page_match` is present.
          url :stable
          strategy :page_match
        end
      end
    RUBY
  end

  it "reports no offenses when a `regex` is specified for `strategy :page_match`" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url :stable
          strategy :page_match
          regex(%r{href=.*?/formula[._-]v?(\\d+(?:\\.\\d+)+)\\.t}i)
        end
      end
    RUBY
  end
end
