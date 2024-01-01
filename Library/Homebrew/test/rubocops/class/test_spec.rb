# frozen_string_literal: true

require "rubocops/class"

describe RuboCop::Cop::FormulaAudit::Test do
  subject(:cop) { described_class.new }

  it "reports and corrects an offense when /usr/local/bin is found in test calls" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'

        test do
          system "/usr/local/bin/test"
                 ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Test: use \#{bin} instead of /usr/local/bin in system
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'

        test do
          system "\#{bin}/test"
        end
      end
    RUBY
  end

  it "reports and corrects an offense when passing 0 as the second parameter to shell_output" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'

        test do
          shell_output("\#{bin}/test", 0)
                                      ^ FormulaAudit/Test: Passing 0 to shell_output() is redundant
        end
      end
    RUBY

    expect_correction(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'

        test do
          shell_output("\#{bin}/test")
        end
      end
    RUBY
  end

  it "reports an offense when there is an empty test block" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'

        test do
        ^^^^^^^ FormulaAudit/Test: `test do` should not be empty
        end
      end
    RUBY
  end

  it "reports an offense when test is falsely true" do
    expect_offense(<<~RUBY)
      class Foo < Formula
        url 'https://brew.sh/foo-1.0.tgz'

        test do
        ^^^^^^^ FormulaAudit/Test: `test do` should contain a real test
          true
        end
      end
    RUBY
  end
end
