# frozen_string_literal: true

require "rubocops/dependency_order"

describe RuboCop::Cop::FormulaAudit::DependencyOrder do
  subject(:cop) { described_class.new }

  context "when auditing `uses_from_macos`" do
    it "reports and corrects incorrectly ordered conditional dependencies" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          uses_from_macos "apple" if build.with? "foo"
          uses_from_macos "foo" => :optional
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "foo" (line 5) should be put before dependency "apple" (line 4)
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          uses_from_macos "foo" => :optional
          uses_from_macos "apple" if build.with? "foo"
        end
      RUBY
    end

    it "reports and corrects incorrectly ordered alphabetical dependencies" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          uses_from_macos "foo"
          uses_from_macos "bar"
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "bar" (line 5) should be put before dependency "foo" (line 4)
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          uses_from_macos "bar"
          uses_from_macos "foo"
        end
      RUBY
    end

    it "reports and corrects incorrectly ordered dependencies that are Requirements" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          uses_from_macos FooRequirement
          uses_from_macos "bar"
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "bar" (line 5) should be put before dependency "FooRequirement" (line 4)
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          uses_from_macos "bar"
          uses_from_macos FooRequirement
        end
      RUBY
    end

    it "reports and corrects wrong conditional order within a spec block" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          head do
            uses_from_macos "apple" if build.with? "foo"
            uses_from_macos "bar"
            ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "bar" (line 6) should be put before dependency "apple" (line 5)
            uses_from_macos "foo" => :optional
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "foo" (line 7) should be put before dependency "apple" (line 5)
          end
          uses_from_macos "apple" if build.with? "foo"
          uses_from_macos "foo" => :optional
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "foo" (line 10) should be put before dependency "apple" (line 9)
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          head do
            uses_from_macos "bar"
            uses_from_macos "foo" => :optional
            uses_from_macos "apple" if build.with? "foo"
          end
          uses_from_macos "foo" => :optional
          uses_from_macos "apple" if build.with? "foo"
        end
      RUBY
    end

    it "reports no offenses if correct order for multiple tags" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          uses_from_macos "bar" => [:build, :test]
          uses_from_macos "foo" => :build
          uses_from_macos "apple"
        end
      RUBY
    end

    it "reports and corrects wrong conditional order within a system block" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          on_arm do
            uses_from_macos "apple" if build.with? "foo"
            uses_from_macos "bar"
            ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "bar" (line 6) should be put before dependency "apple" (line 5)
            uses_from_macos "foo" => :optional
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "foo" (line 7) should be put before dependency "apple" (line 5)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          on_arm do
            uses_from_macos "bar"
            uses_from_macos "foo" => :optional
            uses_from_macos "apple" if build.with? "foo"
          end
        end
      RUBY
    end
  end

  context "when auditing `depends_on`" do
    it "reports and corrects incorrectly ordered conditional dependencies" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on "apple" if build.with? "foo"
          depends_on "foo" => :optional
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "foo" (line 5) should be put before dependency "apple" (line 4)
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on "foo" => :optional
          depends_on "apple" if build.with? "foo"
        end
      RUBY
    end

    it "reports and corrects incorrectly ordered alphabetical dependencies" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on "foo"
          depends_on "bar"
          ^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "bar" (line 5) should be put before dependency "foo" (line 4)
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on "bar"
          depends_on "foo"
        end
      RUBY
    end

    it "reports and corrects incorrectly ordered dependencies that are Requirements" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on FooRequirement
          depends_on "bar"
          ^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "bar" (line 5) should be put before dependency "FooRequirement" (line 4)
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on "bar"
          depends_on FooRequirement
        end
      RUBY
    end

    it "reports and corrects wrong conditional order within a spec block" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          head do
            depends_on "apple" if build.with? "foo"
            depends_on "bar"
            ^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "bar" (line 6) should be put before dependency "apple" (line 5)
            depends_on "foo" => :optional
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "foo" (line 7) should be put before dependency "apple" (line 5)
          end
          depends_on "apple" if build.with? "foo"
          depends_on "foo" => :optional
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "foo" (line 10) should be put before dependency "apple" (line 9)
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          head do
            depends_on "bar"
            depends_on "foo" => :optional
            depends_on "apple" if build.with? "foo"
          end
          depends_on "foo" => :optional
          depends_on "apple" if build.with? "foo"
        end
      RUBY
    end

    it "reports no offenses if correct order for multiple tags" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on "bar" => [:build, :test]
          depends_on "foo" => :build
          depends_on "apple"
        end
      RUBY
    end

    it "reports and corrects wrong conditional order within a system block" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          on_linux do
            depends_on "apple" if build.with? "foo"
            depends_on "bar"
            ^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "bar" (line 6) should be put before dependency "apple" (line 5)
            depends_on "foo" => :optional
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/DependencyOrder: dependency "foo" (line 7) should be put before dependency "apple" (line 5)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          on_linux do
            depends_on "bar"
            depends_on "foo" => :optional
            depends_on "apple" if build.with? "foo"
          end
        end
      RUBY
    end
  end
end
