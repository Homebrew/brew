# typed: strict
# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::RustCheck do
  sig { returns(RuboCop::Cop::FormulaAudit::RustCheck) }
  subject(:cop) { described_class.new }

  context "when auditing rustup dependencies in homebrew/core" do
    it "reports and corrects an offense when a formula depends on `rustup`" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on "rustup"
          ^^^^^^^^^^^^^^^^^^^ FormulaAudit/RustCheck: Formulae in homebrew/core should use `depends_on "rust"` instead of `depends_on "rustup"`.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          depends_on "rust"
        end
      RUBY
    end

    it "reports and corrects an offense when a formula depends on `rustup` to build" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          homepage "https://brew.sh"
          stable do
            url "https://brew.sh/foo-1.0.tgz"
            depends_on "rustup" => [:build, :test]
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/RustCheck: Formulae in homebrew/core should use `depends_on "rust" => [:build, :test]` instead of `depends_on "rustup" => [:build, :test]`.
          end
          depends_on "rustup" => :build
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/RustCheck: Formulae in homebrew/core should use `depends_on "rust" => :build` instead of `depends_on "rustup" => :build`.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"
          stable do
            url "https://brew.sh/foo-1.0.tgz"
            depends_on "rust" => [:build, :test]
          end
          depends_on "rust" => :build
        end
      RUBY
    end

    it "reports no offenses when a formula depends on `rustup` to test" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          homepage "https://brew.sh"
          stable do
            url "https://brew.sh/foo-1.0.tgz"
            depends_on "rustup" => :test
          end
          depends_on "rustup" => :test
        end
      RUBY
    end

    it "reports no offenses when a formula runs `rustup` in test" do
      expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          test do
            system "rustup", "default", "beta"
          end
        end
      RUBY
    end

    it "reports an offense when a formula runs `rustup` in build" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          homepage "https://brew.sh"
          url "https://brew.sh/foo-1.0.tgz"
          def install
            system "rustup", "default", "beta"
                   ^^^^^^^^ FormulaAudit/RustCheck: Formulae in homebrew/core should not use `rustup` at build-time.
            system "/some/path/to/rustup", "default", "beta"
                   ^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/RustCheck: Formulae in homebrew/core should not use `rustup` at build-time.
            system which("rustup"), "default", "beta"
                         ^^^^^^^^ FormulaAudit/RustCheck: Formulae in homebrew/core should not use `rustup` at build-time.
            system formula_opt_bin("rustup")/"rustup", "default", "beta"
                                             ^^^^^^^^ FormulaAudit/RustCheck: Formulae in homebrew/core should not use `rustup` at build-time.
            system "not-rustup"
          end
        end
      RUBY
    end
  end
end
