# typed: strict
# frozen_string_literal: true

require "rubocops/uses_from_macos"

RSpec.describe RuboCop::Cop::FormulaAudit::UsesFromMacos do
  sig { returns(RuboCop::Cop::FormulaAudit::UsesFromMacos) }
  subject(:cop) { described_class.new }

  context "when auditing `uses_from_macos` dependencies" do
    it "reports and corrects an offense when used on non-macOS dependency" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          uses_from_macos "postgresql"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should only be used for macOS dependencies, not 'postgresql'.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on "postgresql"
        end
      RUBY
    end

    it "reports and corrects offenses for multiple non-macOS dependencies and none for valid macOS dependencies" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          uses_from_macos "boost" => :build, since: :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should only be used for macOS dependencies, not 'boost'.
          uses_from_macos "bzip2"
          uses_from_macos "postgresql"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should only be used for macOS dependencies, not 'postgresql'.
          uses_from_macos "zlib"
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on "boost" => :build
          uses_from_macos "bzip2"
          depends_on "postgresql"
          uses_from_macos "zlib"
        end
      RUBY
    end

    it "reports and corrects an offense when used in `depends_on :linux` formula" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on :linux
          uses_from_macos "zlib"
          ^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should not be used when Linux is required.
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on :linux
          depends_on "zlib"
        end
      RUBY
    end

    it "reports and corrects an offense when stable has both `uses_from_macos` and `depends_on :linux`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"

          stable do
            url "https://brew.sh/foo-1.0.tgz"
            depends_on :linux
            uses_from_macos "bzip2"
            ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should not be used when Linux is required.
          end

          head do
            url "https://brew.sh/foo.git"
            uses_from_macos "flex" => :build
          end

          uses_from_macos "zlib"
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"

          stable do
            url "https://brew.sh/foo-1.0.tgz"
            depends_on :linux
            depends_on "bzip2"
          end

          head do
            url "https://brew.sh/foo.git"
            uses_from_macos "flex" => :build
          end

          uses_from_macos "zlib"
        end
      RUBY
    end

    it "reports and corrects an offense when HEAD has both `uses_from_macos` and `depends_on :linux`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"

          stable do
            url "https://brew.sh/foo-1.0.tgz"
            uses_from_macos "bzip2"
          end

          head do
            url "https://brew.sh/foo.git"
            depends_on :linux
            uses_from_macos "flex" => :build
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should not be used when Linux is required.
          end

          uses_from_macos "zlib"
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          homepage "https://brew.sh"

          stable do
            url "https://brew.sh/foo-1.0.tgz"
            uses_from_macos "bzip2"
          end

          head do
            url "https://brew.sh/foo.git"
            depends_on :linux
            depends_on "flex" => :build
          end

          uses_from_macos "zlib"
        end
      RUBY
    end

    it "does not report an offense when `depends_on :linux` is in an arch block" do
      expect_no_offenses(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          uses_from_macos "zlib"

          on_arm do
            depends_on :linux
          end
        end
      RUBY
    end

    # TODO: consider reporting an offense for some of these, e.g. :postgresql
    it "does not report an offense for a dependency name that is not a plain string" do
      expect_no_offenses(<<~'RUBY')
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          uses_from_macos "#{library}" => :build
          uses_from_macos :postgresql
          uses_from_macos "postgresql#{version}"
          uses_from_macos **deps, since: :monterey
          uses_from_macos *args
        end
      RUBY
    end

    it "still reports and corrects the Linux offense for a name that is not a plain string" do
      expect_offense(<<~'RUBY')
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on :linux
          uses_from_macos "postgresql#{version}"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should not be used when Linux is required.
        end
      RUBY

      expect_correction(<<~'RUBY')
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on :linux
          depends_on "postgresql#{version}"
        end
      RUBY
    end
  end

  include_examples "formulae exist", RuboCop::Cop::FormulaAudit::UsesFromMacos::ALLOWED_USES_FROM_MACOS_DEPS
end
