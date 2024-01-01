# frozen_string_literal: true

require "rubocops/lines"

describe RuboCop::Cop::FormulaAudit::ShellVariables do
  subject(:cop) { described_class.new }

  context "when auditing shell variables" do
    it "reports and corrects unexpanded shell variables in `Utils.popen`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            Utils.popen "SHELL=bash foo"
                        ^^^^^^^^^^^^^^^^ FormulaAudit/ShellVariables: Use `Utils.popen({ "SHELL" => "bash" }, "foo")` instead of `Utils.popen "SHELL=bash foo"`
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            Utils.popen { "SHELL" => "bash" }, "foo"
          end
        end
      RUBY
    end

    it "reports and corrects unexpanded shell variables in `Utils.safe_popen_read`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            Utils.safe_popen_read "SHELL=bash foo"
                                  ^^^^^^^^^^^^^^^^ FormulaAudit/ShellVariables: Use `Utils.safe_popen_read({ "SHELL" => "bash" }, "foo")` instead of `Utils.safe_popen_read "SHELL=bash foo"`
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            Utils.safe_popen_read { "SHELL" => "bash" }, "foo"
          end
        end
      RUBY
    end

    it "reports and corrects unexpanded shell variables in `Utils.safe_popen_write`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            Utils.safe_popen_write "SHELL=bash foo"
                                   ^^^^^^^^^^^^^^^^ FormulaAudit/ShellVariables: Use `Utils.safe_popen_write({ "SHELL" => "bash" }, "foo")` instead of `Utils.safe_popen_write "SHELL=bash foo"`
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            Utils.safe_popen_write { "SHELL" => "bash" }, "foo"
          end
        end
      RUBY
    end

    it "reports and corrects unexpanded shell variables while preserving string interpolation" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            Utils.popen "SHELL=bash \#{bin}/foo"
                        ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ShellVariables: Use `Utils.popen({ "SHELL" => "bash" }, "\#{bin}/foo")` instead of `Utils.popen "SHELL=bash \#{bin}/foo"`
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            Utils.popen { "SHELL" => "bash" }, "\#{bin}/foo"
          end
        end
      RUBY
    end
  end
end
