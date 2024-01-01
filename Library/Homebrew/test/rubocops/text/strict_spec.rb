# frozen_string_literal: true

require "rubocops/text"

describe RuboCop::Cop::FormulaAuditStrict::Text do
  subject(:cop) { described_class.new }

  context "when auditing formula text in homebrew/core" do
    it "reports an offense if `env :userpaths` is present" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"

          env :userpaths
          ^^^^^^^^^^^^^^ FormulaAuditStrict/Text: `env :userpaths` in homebrew/core formulae is deprecated
        end
      RUBY
    end

    it "reports an offense if `env :std` is present in homebrew/core" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"

          env :std
          ^^^^^^^^ FormulaAuditStrict/Text: `env :std` in homebrew/core formulae is deprecated
        end
      RUBY
    end

    it %Q(reports an offense if "\#{share}/<formula name>" is present) do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai "\#{share}/foo"
                 ^^^^^^^^^^^^^^ FormulaAuditStrict/Text: Use `\#{pkgshare}` instead of `\#{share}/foo`
          end
        end
      RUBY

      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai "\#{share}/foo/bar"
                 ^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/Text: Use `\#{pkgshare}` instead of `\#{share}/foo`
          end
        end
      RUBY

      expect_offense(<<~RUBY, "/homebrew-core/Formula/foolibc++.rb")
        class Foolibcxx < Formula
          def install
            ohai "\#{share}/foolibc++"
                 ^^^^^^^^^^^^^^^^^^^^ FormulaAuditStrict/Text: Use `\#{pkgshare}` instead of `\#{share}/foolibc++`
          end
        end
      RUBY
    end

    it 'reports an offense if `share/"<formula name>"` is present' do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai share/"foo"
                 ^^^^^^^^^^^ FormulaAuditStrict/Text: Use `pkgshare` instead of `share/"foo"`
          end
        end
      RUBY

      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai share/"foo/bar"
                 ^^^^^^^^^^^^^^^ FormulaAuditStrict/Text: Use `pkgshare` instead of `share/"foo"`
          end
        end
      RUBY

      expect_offense(<<~RUBY, "/homebrew-core/Formula/foolibc++.rb")
        class Foolibcxx < Formula
          def install
            ohai share/"foolibc++"
                 ^^^^^^^^^^^^^^^^^ FormulaAuditStrict/Text: Use `pkgshare` instead of `share/"foolibc++"`
          end
        end
      RUBY
    end

    it %Q(reports no offenses if "\#{share}/<directory name>" doesn't match formula name) do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai "\#{share}/foo-bar"
          end
        end
      RUBY
    end

    it 'reports no offenses if `share/"<formula name>"` is not present' do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai share/"foo-bar"
          end
        end
      RUBY

      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai share/"bar"
          end
        end
      RUBY

      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai share/"bar/foo"
          end
        end
      RUBY
    end

    it %Q(reports no offenses if formula name appears after "\#{share}/<directory name>") do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          def install
            ohai "\#{share}/bar/foo"
          end
        end
      RUBY
    end
  end
end
