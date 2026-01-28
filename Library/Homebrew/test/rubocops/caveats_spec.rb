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
            ^^^^^^^^ FormulaAudit/Caveats: Instead of recommending `setuid` in the caveats, suggest `sudo`.
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

    it "reports an offense if dynamic logic (if/else/unless) is used in caveats" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          homepage "https://brew.sh/foo"
          url "https://brew.sh/foo-1.0.tgz"
          def caveats
            if true
            ^^^^^^^ FormulaAudit/Caveats: Don't use dynamic logic (if/else/unless) in caveats.
              "foo"
            else
              "bar"
            end
          end
        end
      RUBY

      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          homepage "https://brew.sh/foo"
          url "https://brew.sh/foo-1.0.tgz"
          def caveats
            unless false
            ^^^^^^^^^^^^ FormulaAudit/Caveats: Don't use dynamic logic (if/else/unless) in caveats.
              "foo"
            end
          end
        end
      RUBY
    end
  end
end
