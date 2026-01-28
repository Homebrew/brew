# frozen_string_literal: true

require "rubocops/no_autobump"

RSpec.describe RuboCop::Cop::FormulaAudit::NoAutobump do
  subject(:cop) { described_class.new }

  it "reports no offenses if `reason` is acceptable" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "some reason"
      end
    RUBY
  end

  it "reports no offenses if `reason` is acceptable as a symbol" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: :bumped_by_upstream
      end
    RUBY
  end

  it "reports an offense if `reason` is absent" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump!
        ^^^^^^^^^^^^ FormulaAudit/NoAutobumpReason: Add a reason for exclusion from autobump: `no_autobump! because: "..."`
      end
    RUBY
  end

  it "reports an offense is `reason` should not be set manually" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: :extract_plist
                              ^^^^^^^^^^^^^^ FormulaAudit/NoAutobumpReason: `:extract_plist` reason should not be used directly
      end
    RUBY
  end

  it "reports and corrects an offense if `reason` starts with 'it'" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "it does something"
                              ^^^^^^^^^^^^^^^^^^^ FormulaAudit/NoAutobumpReason: Do not start the reason with `it`
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "does something"
      end
    RUBY
  end

  it "reports and corrects an offense if `reason` ends with a period" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "does something."
                              ^^^^^^^^^^^^^^^^^ FormulaAudit/NoAutobumpReason: Do not end the reason with a punctuation mark
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "does something"
      end
    RUBY
  end

  it "reports and corrects an offense if `reason` ends with an exclamation point" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "does something!"
                              ^^^^^^^^^^^^^^^^^ FormulaAudit/NoAutobumpReason: Do not end the reason with a punctuation mark
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "does something"
      end
    RUBY
  end

  it "reports and corrects an offense if `reason` ends with a question mark" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "does something?"
                              ^^^^^^^^^^^^^^^^^ FormulaAudit/NoAutobumpReason: Do not end the reason with a punctuation mark
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'
        no_autobump! because: "does something"
      end
    RUBY
  end
end
