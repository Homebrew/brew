# typed: true
# frozen_string_literal: true

require "rubocops/deprecate_disable"

RSpec.describe RuboCop::Cop::FormulaAudit::DeprecateDisableDate do
  subject(:cop) { described_class.new }

  context "when auditing `deprecate!`" do
    it "reports and corrects an offense if `date` is not ISO 8601 compliant" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "June 25, 2020"
                           ^^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableDate: Use `2020-06-25` to comply with ISO 8601
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-06-25"
        end
      RUBY
    end

    it "reports and corrects an offense if `date` is not ISO 8601 compliant (with `reason`)" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken", date: "June 25, 2020"
                                                 ^^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableDate: Use `2020-06-25` to comply with ISO 8601
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken", date: "2020-06-25"
        end
      RUBY
    end

    it "reports an offense without a correction if `date` is not a valid date" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-06-31"
                           ^^^^^^^^^^^^ FormulaAudit/DeprecateDisableDate: Use an ISO 8601 date (`YYYY-MM-DD`)
        end
      RUBY

      expect_no_corrections
    end

    it "reports an offense without a correction if `date` has no year" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "6/25"
                           ^^^^^^ FormulaAudit/DeprecateDisableDate: Use an ISO 8601 date (`YYYY-MM-DD`)
        end
      RUBY

      expect_no_corrections
    end

    it "reports an offense without a correction if `date` has no day" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "June 2020"
                           ^^^^^^^^^^^ FormulaAudit/DeprecateDisableDate: Use an ISO 8601 date (`YYYY-MM-DD`)
        end
      RUBY

      expect_no_corrections
    end

    it "reports no offenses if `date` is ISO 8601 compliant" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! date: "2020-06-25"
        end
      RUBY
    end

    it "reports no offenses if `date` is ISO 8601 compliant (with `reason`)" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken", date: "2020-06-25"
        end
      RUBY
    end

    it "reports no offenses if no `date` is specified" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate!
        end
      RUBY
    end

    it "reports no offenses if no `date` is specified (with `reason`)" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecate! because: "is broken"
        end
      RUBY
    end
  end

  context "when auditing `disable!`" do
    it "reports and corrects an offense if `date` is not ISO 8601 compliant" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "June 25, 2020"
                         ^^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableDate: Use `2020-06-25` to comply with ISO 8601
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-06-25"
        end
      RUBY
    end

    it "reports and corrects an offense if `date` is not ISO 8601 compliant (with `reason`)" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken", date: "June 25, 2020"
                                               ^^^^^^^^^^^^^^^ FormulaAudit/DeprecateDisableDate: Use `2020-06-25` to comply with ISO 8601
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken", date: "2020-06-25"
        end
      RUBY
    end

    it "reports no offenses if `date` is ISO 8601 compliant" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! date: "2020-06-25"
        end
      RUBY
    end

    it "reports no offenses if `date` is ISO 8601 compliant (with `reason`)" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken", date: "2020-06-25"
        end
      RUBY
    end

    it "reports no offenses if no `date` is specified" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable!
        end
      RUBY
    end

    it "reports no offenses if no `date` is specified (with `reason`)" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          disable! because: "is broken"
        end
      RUBY
    end
  end
end
