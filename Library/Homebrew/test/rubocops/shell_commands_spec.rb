# frozen_string_literal: true

require "rubocops/shell_commands"

module RuboCop
  module Cop
    module Homebrew
      describe ShellCommands do
        subject(:cop) { described_class.new }

        context "when auditing shell commands" do
          it "reports and corrects an offense when `system` arguments should be separated" do
            expect_offense(<<~RUBY)
              class Foo < Formula
                def install
                  system "foo bar"
                         ^^^^^^^^^ Homebrew/ShellCommands: Separate `system` commands into `"foo", "bar"`
                end
              end
            RUBY

            expect_correction(<<~RUBY)
              class Foo < Formula
                def install
                  system "foo", "bar"
                end
              end
            RUBY
          end

          it "reports and corrects an offense when `system` arguments involving interpolation should be separated" do
            expect_offense(<<~RUBY)
              class Foo < Formula
                def install
                  system "\#{bin}/foo bar"
                         ^^^^^^^^^^^^^^^^ Homebrew/ShellCommands: Separate `system` commands into `"\#{bin}/foo", "bar"`
                end
              end
            RUBY

            expect_correction(<<~RUBY)
              class Foo < Formula
                def install
                  system "\#{bin}/foo", "bar"
                end
              end
            RUBY
          end

          it "reports no offenses when `system` with metacharacter arguments are called" do
            expect_no_offenses(<<~RUBY)
              class Foo < Formula
                def install
                  system "foo bar > baz"
                end
              end
            RUBY
          end

          it "reports no offenses when trailing arguments to `system` are unseparated" do
            expect_no_offenses(<<~RUBY)
              class Foo < Formula
                def install
                  system "foo", "bar baz"
                end
              end
            RUBY
          end

          it "reports no offenses when `Utils.popen` arguments are unseparated" do
            expect_no_offenses(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen("foo bar")
                end
              end
            RUBY
          end

          it "reports and corrects an offense when `Utils.popen_read` arguments are unseparated" do
            expect_offense(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_read("foo bar")
                                   ^^^^^^^^^ Homebrew/ShellCommands: Separate `Utils.popen_read` commands into `"foo", "bar"`
                end
              end
            RUBY

            expect_correction(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_read("foo", "bar")
                end
              end
            RUBY
          end

          it "reports and corrects an offense when `Utils.safe_popen_read` arguments are unseparated" do
            expect_offense(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.safe_popen_read("foo bar")
                                        ^^^^^^^^^ Homebrew/ShellCommands: Separate `Utils.safe_popen_read` commands into `"foo", "bar"`
                end
              end
            RUBY

            expect_correction(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.safe_popen_read("foo", "bar")
                end
              end
            RUBY
          end

          it "reports and corrects an offense when `Utils.popen_write` arguments are unseparated" do
            expect_offense(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_write("foo bar")
                                    ^^^^^^^^^ Homebrew/ShellCommands: Separate `Utils.popen_write` commands into `"foo", "bar"`
                end
              end
            RUBY

            expect_correction(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_write("foo", "bar")
                end
              end
            RUBY
          end

          it "reports and corrects an offense when `Utils.safe_popen_write` arguments are unseparated" do
            expect_offense(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.safe_popen_write("foo bar")
                                         ^^^^^^^^^ Homebrew/ShellCommands: Separate `Utils.safe_popen_write` commands into `"foo", "bar"`
                end
              end
            RUBY

            expect_correction(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.safe_popen_write("foo", "bar")
                end
              end
            RUBY
          end

          it "reports and corrects an offense when `Utils.popen_read` arguments with interpolation are unseparated" do
            expect_offense(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_read("\#{bin}/foo bar")
                                   ^^^^^^^^^^^^^^^^ Homebrew/ShellCommands: Separate `Utils.popen_read` commands into `"\#{bin}/foo", "bar"`
                end
              end
            RUBY

            expect_correction(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_read("\#{bin}/foo", "bar")
                end
              end
            RUBY
          end

          it "reports no offenses when `Utils.popen_read` arguments with metacharacters are unseparated" do
            expect_no_offenses(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_read("foo bar > baz")
                end
              end
            RUBY
          end

          it "reports no offenses when trailing arguments to `Utils.popen_read` are unseparated" do
            expect_no_offenses(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_read("foo", "bar baz")
                end
              end
            RUBY
          end

          it "reports and corrects an offense when `Utils.popen_read` arguments are unseparated after a shell env" do
            expect_offense(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_read({ "SHELL" => "bash"}, "foo bar")
                                                         ^^^^^^^^^ Homebrew/ShellCommands: Separate `Utils.popen_read` commands into `"foo", "bar"`
                end
              end
            RUBY

            expect_correction(<<~RUBY)
              class Foo < Formula
                def install
                  Utils.popen_read({ "SHELL" => "bash"}, "foo", "bar")
                end
              end
            RUBY
          end
        end
      end

      describe ExecShellMetacharacters do
        subject(:cop) { described_class.new }

        context "when auditing exec calls" do
          it "reports aan offense when output piping is used" do
            expect_offense(<<~RUBY)
              fork do
                exec "foo bar > output"
                     ^^^^^^^^^^^^^^^^^^ Homebrew/ExecShellMetacharacters: Don't use shell metacharacters in `exec`. Implement the logic in Ruby instead, using methods like `$stdout.reopen`.
              end
            RUBY
          end

          it "reports no offenses when no metacharacters are used" do
            expect_no_offenses(<<~RUBY)
              fork do
                exec "foo bar"
              end
            RUBY
          end
        end
      end
    end
  end
end
