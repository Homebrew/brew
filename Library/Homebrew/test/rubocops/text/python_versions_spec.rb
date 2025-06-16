# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::PythonVersions do
  subject(:cop) { described_class.new }

  context "when auditing Python versions" do
    it "reports no offenses for Python with no dependency" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            puts "python@3.8"
          end
        end
      RUBY
    end

    it "reports no offenses for unversioned Python references" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9"

          def install
            puts "python"
          end
        end
      RUBY
    end

    it "reports no offenses for Python with no version" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9"

          def install
            puts "python3"
          end
        end
      RUBY
    end

    it "reports no offenses when a Python reference matches its dependency" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9"

          def install
            puts "python@3.9"
          end
        end
      RUBY
    end

    it "reports no offenses when a Python reference matches its dependency without `@`" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9"

          def install
            puts "python3.9"
          end
        end
      RUBY
    end

    it "reports no offenses when a Python reference matches its two-digit dependency" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.10"

          def install
            puts "python@3.10"
          end
        end
      RUBY
    end

    it "reports no offenses when a Python reference matches its two-digit dependency without `@`" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.10"

          def install
            puts "python3.10"
          end
        end
      RUBY
    end

    it "reports and corrects Python references with mismatched versions" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9"

          def install
            puts "python@3.8"
                 ^^^^^^^^^^^^ FormulaAudit/PythonVersions: References to `python@3.8` should match the specified python dependency (`python@3.9`)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9"

          def install
            puts "python@3.9"
          end
        end
      RUBY
    end

    it "reports and corrects Python references with mismatched versions without `@`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9"

          def install
            puts "python3.8"
                 ^^^^^^^^^^^ FormulaAudit/PythonVersions: References to `python3.8` should match the specified python dependency (`python3.9`)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9"

          def install
            puts "python3.9"
          end
        end
      RUBY
    end

    it "reports and corrects Python references with mismatched two-digit versions" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.11"

          def install
            puts "python@3.10"
                 ^^^^^^^^^^^^^ FormulaAudit/PythonVersions: References to `python@3.10` should match the specified python dependency (`python@3.11`)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.11"

          def install
            puts "python@3.11"
          end
        end
      RUBY
    end

    it "reports and corrects Python references with mismatched two-digit versions without `@`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.11"

          def install
            puts "python3.10"
                 ^^^^^^^^^^^^ FormulaAudit/PythonVersions: References to `python3.10` should match the specified python dependency (`python3.11`)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.11"

          def install
            puts "python3.11"
          end
        end
      RUBY
    end

    it "reports no offenses for multiple non-runtime Python dependencies" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9" => :build
          depends_on "python@3.10" => :test

          def install
            puts "python3.9"
          end

          test do
            puts "python3.10"
          end
        end
      RUBY
    end

    it "reports and corrects Python references that mismatch single non-runtime Python dependency" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9" => :build

          def install
            puts "python@3.8"
                 ^^^^^^^^^^^^ FormulaAudit/PythonVersions: References to `python@3.8` should match the specified python dependency (`python@3.9`)
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.9" => :build

          def install
            puts "python@3.9"
          end
        end
      RUBY
    end
  end
end
