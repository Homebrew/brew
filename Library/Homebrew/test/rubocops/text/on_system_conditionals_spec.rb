# frozen_string_literal: true

require "rubocops/lines"

describe RuboCop::Cop::FormulaAudit::OnSystemConditionals do
  subject(:cop) { described_class.new }

  context "when auditing OS conditionals" do
    it "reports an offense when `OS.linux?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if OS.linux?
          ^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if OS.linux?`, use `on_linux do` instead.
            url 'https://brew.sh/linux-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_linux do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        on_macos do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `OS.mac?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if OS.mac?
          ^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if OS.mac?`, use `on_macos do` instead.
            url 'https://brew.sh/mac-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_macos do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        on_linux do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `on_macos` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_macos do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_macos` in `def install`, use `if OS.mac?` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if OS.mac?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_linux` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_linux do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_linux` in `def install`, use `if OS.linux?` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if OS.linux?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_macos` is used in test block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            on_macos do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_macos` in `test do`, use `if OS.mac?` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            if OS.mac?
              true
            end
          end
        end
      RUBY
    end
  end

  context "when auditing Hardware::CPU conditionals" do
    it "reports an offense when `Hardware::CPU.arm?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if Hardware::CPU.arm?
          ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if Hardware::CPU.arm?`, use `on_arm do` instead.
            url 'https://brew.sh/linux-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_arm do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        on_intel do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `Hardware::CPU.intel?` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if Hardware::CPU.intel?
          ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if Hardware::CPU.intel?`, use `on_intel do` instead.
            url 'https://brew.sh/mac-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_intel do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        on_arm do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `on_intel` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_intel do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_intel` in `def install`, use `if Hardware::CPU.intel?` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if Hardware::CPU.intel?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_arm` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_arm do
            ^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_arm` in `def install`, use `if Hardware::CPU.arm?` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if Hardware::CPU.arm?
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_intel` is used in test block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            on_intel do
            ^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_intel` in `test do`, use `if Hardware::CPU.intel?` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            if Hardware::CPU.intel?
              true
            end
          end
        end
      RUBY
    end
  end

  context "when auditing MacOS.version conditionals" do
    it "reports an offense when `MacOS.version ==` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version == :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if MacOS.version == :monterey`, use `on_monterey do` instead.
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_monterey do
        url 'https://brew.sh/linux-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `MacOS.version <=` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version <= :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if MacOS.version <= :monterey`, use `on_system :linux, macos: :monterey_or_older do` instead.
            url 'https://brew.sh/mac-1.0.tgz'
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          on_system :linux, macos: :monterey_or_older do
        url 'https://brew.sh/mac-1.0.tgz'
        end
        end
      RUBY
    end

    it "reports an offense when `MacOS.version <` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version < :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if MacOS.version < :monterey`, use `on_system do` instead.
            url 'https://brew.sh/mac-1.0.tgz'
          end
        end
      RUBY
    end

    it "reports an offense when `MacOS.version >=` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version >= :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if MacOS.version >= :monterey`, use `on_monterey :or_newer do` instead.
            url 'https://brew.sh/mac-1.0.tgz'
          else
            url 'https://brew.sh/linux-1.0.tgz'
          end
        end
      RUBY
    end

    it "reports an offense when `MacOS.version >` is used on Formula class" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          if MacOS.version > :monterey
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `if MacOS.version > :monterey`, use `on_monterey do` instead.
            url 'https://brew.sh/mac-1.0.tgz'
          end
        end
      RUBY
    end

    it "reports an offense when `on_monterey` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_monterey do
            ^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_monterey` in `def install`, use `if MacOS.version == :monterey` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if MacOS.version == :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_monterey :or_older` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_monterey :or_older do
            ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_monterey :or_older` in `def install`, use `if MacOS.version <= :monterey` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if MacOS.version <= :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_monterey :or_newer` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_monterey :or_newer do
            ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_monterey :or_newer` in `def install`, use `if MacOS.version >= :monterey` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if MacOS.version >= :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_system :linux, macos: :monterey_or_newer` is used in install method" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            on_system :linux, macos: :monterey_or_newer do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_system :linux, macos: :monterey_or_newer` in `def install`, use `if OS.linux? || MacOS.version >= :monterey` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def install
            if OS.linux? || MacOS.version >= :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_monterey` is used in test block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            on_monterey do
            ^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_monterey` in `test do`, use `if MacOS.version == :monterey` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            if MacOS.version == :monterey
              true
            end
          end
        end
      RUBY
    end

    it "reports an offense when `on_system :linux, macos: :monterey` is used in test block" do
      expect_offense(<<~RUBY, "/homebrew-core/Formula/foo.rb")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            on_system :linux, macos: :monterey do
            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OnSystemConditionals: Don't use `on_system :linux, macos: :monterey` in `test do`, use `if OS.linux? || MacOS.version == :monterey` instead.
              true
            end
          end
        end
      RUBY

      expect_correction(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          test do
            if OS.linux? || MacOS.version == :monterey
              true
            end
          end
        end
      RUBY
    end
  end
end
