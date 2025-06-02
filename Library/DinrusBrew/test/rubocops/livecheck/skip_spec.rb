# frozen_string_literal: true

require "rubocops/livecheck"

RSpec.describe RuboCop::Cop::FormulaAudit::LivecheckSkip do
  subject(:cop) { described_class.new }

  it "reports an offense when a skipped formula's `livecheck` block contains other information" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
        ^^^^^^^^^^^^ FormulaAudit/LivecheckSkip: Skipped formulae must not contain other livecheck information.
          skip "Not maintained"
          url :stable
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          skip "Not maintained"
        end
      end
    RUBY
  end

  it "reports no offenses when a skipped formula's `livecheck` block contains no other information" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          skip "Not maintained"
        end
      end
    RUBY
  end
end
