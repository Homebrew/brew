# frozen_string_literal: true

require "rubocops/caveats"

RSpec.describe RuboCop::Cop::FormulaAudit::Caveats do
  subject(:cop) { described_class.new }

  context "when auditing `caveats`" do
    it "reports an offense if `setuid` is mentioned" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh/foo"
          url "https://brew.sh/foo-1.0.tgz"
           def caveats
            "setuid"
            ^^^^^^^^ FormulaAudit/Caveats: Don't recommend `setuid` in the caveats, suggest `sudo` instead.
          end
        end
      RUBY
    end

    it "reports an offense if an escape character is present" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh/foo"
          url "https://brew.sh/foo-1.0.tgz"
           def caveats
            "\\x1B"
            ^^^^^^ FormulaAudit/Caveats: Don't use ANSI escape codes in the caveats.
          end
        end
      RUBY

      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh/foo"
          url "https://brew.sh/foo-1.0.tgz"
           def caveats
            "\\u001b"
            ^^^^^^^^ FormulaAudit/Caveats: Don't use ANSI escape codes in the caveats.
          end
        end
      RUBY
    end
  end
end
