# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::StdNpmArgs do
  subject(:cop) { described_class.new }

  context "when auditing node formulae" do
    it "reports an offense when `npm install` is called without std_npm_args arguments" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "npm", "install"
            ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/StdNpmArgs: Use `std_npm_args` for npm install
          end
        end
      RUBY
    end

    it "reports and corrects an offense when using local_npm_install_args" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "npm", "install", *Language::Node.local_npm_install_args, "--production"
                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/StdNpmArgs: Use `std_npm_args` instead of `local_npm_install_args`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            system "npm", "install", *std_npm_args(prefix: false), "--production"
          end
        end
      RUBY
    end

    it "reports and corrects an offense when using std_npm_install_args with libexec" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "npm", "install", *Language::Node.std_npm_install_args(libexec), "--production"
                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/StdNpmArgs: Use `std_npm_args` instead of `std_npm_install_args`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            system "npm", "install", *std_npm_args, "--production"
          end
        end
      RUBY
    end

    it "reports and corrects an offense when using std_npm_install_args without libexec" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            system "npm", "install", *Language::Node.std_npm_install_args(buildpath), "--production"
                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/StdNpmArgs: Use `std_npm_args` instead of `std_npm_install_args`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            system "npm", "install", *std_npm_args(prefix: buildpath), "--production"
          end
        end
      RUBY
    end

    it "does not report an offense when using std_npm_args" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install
            system "npm", "install", *std_npm_args
          end
        end
      RUBY
    end
  end
end
