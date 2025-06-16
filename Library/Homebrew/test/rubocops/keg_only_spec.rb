# frozen_string_literal: true

require "rubocops/keg_only"

RSpec.describe RuboCop::Cop::FormulaAudit::KegOnly do
  subject(:cop) { described_class.new }

  it "reports and corrects an offense when the `keg_only` reason is capitalized" do
    expect_offense(<<~RUBY)
      class Foo < Formula

        url "https://brew.sh/foo-1.0.tgz"
        homepage "https://brew.sh"

        keg_only "Because why not"
                 ^^^^^^^^^^^^^^^^^ FormulaAudit/KegOnly: 'Because' from the `keg_only` reason should be 'because'.
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula

        url "https://brew.sh/foo-1.0.tgz"
        homepage "https://brew.sh"

        keg_only "because why not"
      end
    RUBY
  end

  it "reports and corrects an offense when the `keg_only` reason ends with a period" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        homepage "https://brew.sh"

        keg_only "ending with a period."
                 ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/KegOnly: `keg_only` reason should not end with a period.
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        homepage "https://brew.sh"

        keg_only "ending with a period"
      end
    RUBY
  end

  it "reports no offenses when a `keg_only` reason is a block" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        homepage "https://brew.sh"

        keg_only <<~EOF
          this line starts with a lowercase word.

          This line does not but that shouldn't be a
          problem
        EOF
      end
    RUBY
  end

  it "reports no offenses if a capitalized `keg-only` reason is an exempt proper noun" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        homepage "https://brew.sh"

        keg_only "Apple ships foo in the CLT package"
      end
    RUBY
  end

  it "reports no offenses if a capitalized `keg_only` reason is the formula's name" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"

        keg_only "Foo is the formula name hence downcasing is not required"
      end
    RUBY
  end
end
