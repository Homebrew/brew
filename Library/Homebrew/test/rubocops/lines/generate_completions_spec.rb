# frozen_string_literal: true

require "rubocops/lines"

describe RuboCop::Cop::FormulaAudit do
  describe RuboCop::Cop::FormulaAudit::GenerateCompletionsDSL do
    subject(:cop) { described_class.new }

    it "reports an offense when writing to a shell completions file directly" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          name "foo"

          def install
            (bash_completion/"foo").write Utils.safe_popen_read(bin/"foo", "completions", "bash")
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/GenerateCompletionsDSL: Use `generate_completions_from_executable(bin/"foo", "completions", shells: [:bash])` instead of `(bash_completion/"foo").write Utils.safe_popen_read(bin/"foo", "completions", "bash")`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          name "foo"

          def install
            generate_completions_from_executable(bin/"foo", "completions", shells: [:bash])
          end
        end
      RUBY
    end

    it "reports an offense when writing to a shell completions file differing from the formula name" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo-cli.rb")
        class FooCli < Formula
          name "foo-cli"

          def install
            (bash_completion/"foo").write Utils.safe_popen_read(bin/"foo", "completions", "bash")
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/GenerateCompletionsDSL: Use `generate_completions_from_executable(bin/"foo", "completions", base_name: "foo", shells: [:bash])` instead of `(bash_completion/"foo").write Utils.safe_popen_read(bin/"foo", "completions", "bash")`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class FooCli < Formula
          name "foo-cli"

          def install
            generate_completions_from_executable(bin/"foo", "completions", base_name: "foo", shells: [:bash])
          end
        end
      RUBY
    end

    it "reports an offense when writing to a shell completions file using an arg for the shell parameter" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          name "foo"

          def install
            (bash_completion/"foo").write Utils.safe_popen_read(bin/"foo", "completions", "--shell=bash")
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/GenerateCompletionsDSL: Use `generate_completions_from_executable(bin/"foo", "completions", shells: [:bash], shell_parameter_format: :arg)` instead of `(bash_completion/"foo").write Utils.safe_popen_read(bin/"foo", "completions", "--shell=bash")`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          name "foo"

          def install
            generate_completions_from_executable(bin/"foo", "completions", shells: [:bash], shell_parameter_format: :arg)
          end
        end
      RUBY
    end

    it "reports an offense when writing to a shell completions file using a custom flag for the shell parameter" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          name "foo"

          def install
            (bash_completion/"foo").write Utils.safe_popen_read(bin/"foo", "completions", "--completion-script-bash")
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/GenerateCompletionsDSL: Use `generate_completions_from_executable(bin/"foo", "completions", shells: [:bash], shell_parameter_format: "--completion-script-")` instead of `(bash_completion/"foo").write Utils.safe_popen_read(bin/"foo", "completions", "--completion-script-bash")`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          name "foo"

          def install
            generate_completions_from_executable(bin/"foo", "completions", shells: [:bash], shell_parameter_format: "--completion-script-")
          end
        end
      RUBY
    end

    it "reports an offense when writing to a completions file indirectly" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          name "foo"

          def install
            output = Utils.safe_popen_read(bin/"foo", "completions", "bash")
            (bash_completion/"foo").write output
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/GenerateCompletionsDSL: Use `generate_completions_from_executable` DSL instead of `(bash_completion/"foo").write output`.
          end
        end
      RUBY
    end
  end

  describe RuboCop::Cop::FormulaAudit::SingleGenerateCompletionsDSLCall do
    subject(:cop) { described_class.new }

    it "reports an offense when using multiple #generate_completions_from_executable calls for different shells" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          name "foo"

          def install
            generate_completions_from_executable(bin/"foo", "completions", shells: [:bash])
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/SingleGenerateCompletionsDSLCall: Use a single `generate_completions_from_executable` call combining all specified shells.
            generate_completions_from_executable(bin/"foo", "completions", shells: [:zsh])
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/SingleGenerateCompletionsDSLCall: Use a single `generate_completions_from_executable` call combining all specified shells.
            generate_completions_from_executable(bin/"foo", "completions", shells: [:fish])
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/SingleGenerateCompletionsDSLCall: Use `generate_completions_from_executable(bin/"foo", "completions")` instead of `generate_completions_from_executable(bin/"foo", "completions", shells: [:fish])`.
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          name "foo"

          def install
            generate_completions_from_executable(bin/"foo", "completions")
          end
        end
      RUBY
    end
  end
end
