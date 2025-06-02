# frozen_string_literal: true

require "rubocops/text"

RSpec.describe RuboCop::Cop::FormulaAuditStrict::Text do
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

    context "for interpolated bin paths" do
      it 'reports an offense & autocorrects if "\#{bin}/<formula_name>" or other dashed binaries too are present' do
        expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
          class Foo < Formula
            test do
              system "\#{bin}/foo", "-v"
                     ^^^^^^^^^^^^ FormulaAuditStrict/Text: Use `bin/"foo"` instead of `"\#{bin}/foo"`
              system "\#{bin}/foo-bar", "-v"
                     ^^^^^^^^^^^^^^^^ FormulaAuditStrict/Text: Use `bin/"foo-bar"` instead of `"\#{bin}/foo-bar"`
            end
          end
        RUBY

        expect_correction(<<~RUBY)
          class Foo < Formula
            test do
              system bin/"foo", "-v"
              system bin/"foo-bar", "-v"
            end
          end
        RUBY
      end

      it 'does not report an offense if \#{bin}/foo and then a space and more text' do
        expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
          class Foo < Formula
            test do
              shell_output("\#{bin}/foo --version")
              assert_match "help", shell_output("\#{bin}/foo-something --help 2>&1")
              assert_match "OK", shell_output("\#{bin}/foo-something_else --check 2>&1")
            end
          end
        RUBY
      end
    end

    it 'does not report an offense if "\#{bin}/foo" is in a word array' do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          test do
            cmd = %W[
              \#{bin}/foo
              version
            ]
            assert_match version.to_s, shell_output(cmd)
          end
        end
      RUBY
    end
  end
end
