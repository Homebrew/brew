# typed: true
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

    it "reports and corrects hardcoded `python = \"pythonX.Y\"` assignments" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def install
            python = "python3.12"
                     ^^^^^^^^^^^^ FormulaAudit/PythonVersions: Use `python = python3` instead of a hardcoded Python executable.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def install
            python = python3
          end
        end
      RUBY
    end

    it "reports no offenses for dynamic python assignments" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def install
            python = python3
          end
        end
      RUBY
    end

    it "reports and corrects hardcoded `python3 = \"pythonX.Y\"` assignments" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def install
            python3 = "python3.12"
                      ^^^^^^^^^^^^ FormulaAudit/PythonVersions: Use `python3` directly instead of assigning a hardcoded Python executable.
            system python3, "--version"
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def install
            system python3, "--version"
          end
        end
      RUBY
    end

    it "reports and corrects a hardcoded version matching the python dependency" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def install
            python = "python3.14"
                     ^^^^^^^^^^^^ FormulaAudit/PythonVersions: Use `python = python3` instead of a hardcoded Python executable.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def install
            python = python3
          end
        end
      RUBY
    end

    it "reports no offenses for hardcoded python version assigned to non-python local" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def install
            interpreter = "python3.14"
          end
        end
      RUBY
    end

    it "reports and corrects assignments with a tagged Python dependency" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14" => [:build, :test]

          test do
            python = "python3.14"
                     ^^^^^^^^^^^^ FormulaAudit/PythonVersions: Use `python = python3` instead of a hardcoded Python executable.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14" => [:build, :test]

          test do
            python = python3
          end
        end
      RUBY
    end

    it "reports and corrects assignments with duplicate Python dependencies" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "homebrew/core/python@3.14" => :build
          depends_on "python@3.14" => :test

          def install
            python = "python3.14"
                     ^^^^^^^^^^^^ FormulaAudit/PythonVersions: Use `python = python3` instead of a hardcoded Python executable.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          depends_on "homebrew/core/python@3.14" => :build
          depends_on "python@3.14" => :test

          def install
            python = python3
          end
        end
      RUBY
    end

    it "reports no offenses for assignments without a Python dependency" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            python = "python3.14"
          end
        end
      RUBY
    end

    it "reports no offenses for assignments with multiple Python dependencies" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.13"
          depends_on "python@3.14" => :test

          def install
            python = "python3.13"
          end

          test do
            python3 = "python3.14"
          end
        end
      RUBY
    end

    it "reports no offenses for assignments of formula names or paths" do
      expect_no_offenses(<<~'RUBY')
        class Foo < Formula
          depends_on "python@3.14"

          def install
            python = "python@3.14"
            python3 = "bin/python3.14"
            python = "python3.14\npython3.14"
          end
        end
      RUBY
    end

    it "reports no offenses for Python 2 assignments" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@2.7"

          def install
            python = "python2.7"
          end
        end
      RUBY
    end

    it "reports no offenses for assignments outside instance methods and tests" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"
          python = "python3.14"

          def self.foo
            python3 = "python3.14"
          end
        end
      RUBY
    end

    it "reports no offenses for assignments when the python3 method is overridden" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          depends_on "python@3.14"

          def python3
            "python3.14"
          end

          def install
            python = "python3.14"
          end
        end
      RUBY
    end
  end
end
