# frozen_string_literal: true

require "rubocops/deprecate_disable"

describe RuboCop::Cop::FormulaAudit::DeprecateDisableReason do
  subject(:cop) { described_class.new }

  context "when auditing `deprecate!`" do
    it "reports no offenses if `reason` is acceptable" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken"
        end
      RUBY
    end

    it "reports no offenses if `reason` is acceptable as a symbol" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: :does_not_build
        end
      RUBY
    end

    it "reports no offenses if `reason` is acceptable (with `date`)" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-08-28", because: "is broken"
        end
      RUBY
    end

    it "reports no offenses if `reason` is acceptable as a symbol (with `date`)" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-08-28", because: :does_not_build
        end
      RUBY
    end

    it "reports an offense if `reason` is absent" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate!
          ^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Add a reason for deprecation: `deprecate! because: "..."`
        end
      RUBY
    end

    it "reports an offense if `reason` is absent (with `date`)" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-08-28"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Add a reason for deprecation: `deprecate! because: "..."`
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` starts with 'it'" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "it is broken"
                              ^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not start the reason with `it`
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` starts with 'it' (with `date`)" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-08-28", because: "it is broken"
                                                  ^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not start the reason with `it`
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-08-28", because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` ends with a period" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken."
                              ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not end the reason with a punctuation mark
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` ends with an exclamation point" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken!"
                              ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not end the reason with a punctuation mark
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` ends with a question mark" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken?"
                              ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not end the reason with a punctuation mark
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` ends with a period (with `date`)" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-08-28", because: "is broken."
                                                  ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not end the reason with a punctuation mark
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-08-28", because: "is broken"
        end
      RUBY
    end
  end

  context "when auditing `disable!`" do
    it "reports no offenses if `reason` is acceptable" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken"
        end
      RUBY
    end

    it "reports no offenses if `reason` is acceptable as a symbol" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: :does_not_build
        end
      RUBY
    end

    it "reports no offenses if `reason` is acceptable (with `date`)" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-08-28", because: "is broken"
        end
      RUBY
    end

    it "reports no offenses if `reason` is acceptable as a symbol (with `date`)" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-08-28", because: :does_not_build
        end
      RUBY
    end

    it "reports an offense if `reason` is absent" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable!
          ^^^^^^^^ FormulaAudit/DeprecateDisableReason: Add a reason for disabling: `disable! because: "..."`
        end
      RUBY
    end

    it "reports an offense if `reason` is absent (with `date`)" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-08-28"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Add a reason for disabling: `disable! because: "..."`
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` starts with 'it'" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "it is broken"
                            ^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not start the reason with `it`
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` starts with 'it' (with `date`)" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-08-28", because: "it is broken"
                                                ^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not start the reason with `it`
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-08-28", because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` ends with a period" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken."
                            ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not end the reason with a punctuation mark
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` ends with an exclamation point" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken!"
                            ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not end the reason with a punctuation mark
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` ends with a question mark" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken?"
                            ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not end the reason with a punctuation mark
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken"
        end
      RUBY
    end

    it "reports and corrects an offense if `reason` ends with a period (with `date`)" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-08-28", because: "is broken."
                                                ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableReason: Do not end the reason with a punctuation mark
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-08-28", because: "is broken"
        end
      RUBY
    end
  end
end
