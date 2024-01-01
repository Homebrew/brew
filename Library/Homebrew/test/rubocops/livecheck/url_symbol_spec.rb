# frozen_string_literal: true

require "rubocops/livecheck"

describe RuboCop::Cop::FormulaAudit::LivecheckUrlSymbol do
  subject(:cop) { described_class.new }

  it "reports an offense when the `url` specified in the livecheck block is identical to a formula URL" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url "https://brew.sh/foo-1.0.tgz"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/LivecheckUrlSymbol: Use `url :stable`
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url :stable
        end
      end
    RUBY
  end

  it "reports no offenses when the `url` specified in the livecheck block is not identical to a formula URL" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        livecheck do
          url "https://brew.sh/foo/releases/"
        end
      end
    RUBY
  end
end
