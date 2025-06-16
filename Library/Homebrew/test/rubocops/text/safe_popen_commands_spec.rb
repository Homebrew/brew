# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::SafePopenCommands do
  subject(:cop) { described_class.new }

  context "when auditing popen commands" do
    it "reports and corrects `Utils.popen_read` usage" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            Utils.popen_read "foo"
            ^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/SafePopenCommands: Use `Utils.safe_popen_read` instead of `Utils.popen_read`
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            Utils.safe_popen_read "foo"
          end
        end
      RUBY
    end

    it "reports and corrects `Utils.popen_write` usage" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          def install
            Utils.popen_write "foo"
            ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/SafePopenCommands: Use `Utils.safe_popen_write` instead of `Utils.popen_write`
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          def install
            Utils.safe_popen_write "foo"
          end
        end
      RUBY
    end

    it "does not report an offense when `Utils.popen_read` is used in a test block" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          def install; end
          test do
            Utils.popen_read "foo"
          end
        end
      RUBY
    end
  end
end
