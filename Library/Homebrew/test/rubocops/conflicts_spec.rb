# frozen_string_literal: true

require "rubocops/conflicts"

describe RuboCop::Cop::FormulaAudit::Conflicts do
  subject(:cop) { described_class.new }

  context "when auditing `conflicts_with`" do
    it "reports and corrects an offense if reason is capitalized" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          conflicts_with "bar", :because => "Reason"
                                            ^^^^^^^^ FormulaAudit/Conflicts: 'Reason' from the `conflicts_with` reason should be 'reason'.
          conflicts_with "baz", :because => "Foo is the formula name which does not require downcasing"
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          conflicts_with "bar", :because => "reason"
          conflicts_with "baz", :because => "Foo is the formula name which does not require downcasing"
        end
      RUBY
    end

    it "reports and corrects an offense if reason ends with a period" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          conflicts_with "bar", "baz", :because => "reason."
                                                   ^^^^^^^^^ FormulaAudit/Conflicts: `conflicts_with` reason should not end with a period.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          conflicts_with "bar", "baz", :because => "reason"
        end
      RUBY
    end

    it "reports an offense if it is present in a versioned formula" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo@2.0.rb")
        class FooAT20 < Formula
          url 'https://brew.sh/foo-2.0.tgz'
          conflicts_with "mysql", "mariadb"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Conflicts: Versioned formulae should not use `conflicts_with`. Use `keg_only :versioned_formula` instead.
        end
      RUBY
    end

    it "reports no offenses if it is not present" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo@2.0.rb")
        class FooAT20 < Formula
          url 'https://brew.sh/foo-2.0.tgz'
          homepage "https://brew.sh"
        end
      RUBY
    end
  end
end
