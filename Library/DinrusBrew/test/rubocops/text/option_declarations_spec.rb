# frozen_string_literal: true

require "rubocops/lines"

RSpec.describe RuboCop::Cop::FormulaAudit::OptionDeclarations do
  subject(:cop) { described_class.new }

  context "when auditing options" do
    it "reports an offense when `build.without?` is used in homebrew/core" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def install
            build.without? "bar"
            ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Formulae in homebrew/core should not use `build.without?`.
          end
        end
      RUBY
    end

    it "reports an offense when `build.with?` is used in homebrew/core" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def install
            build.with? "bar"
            ^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Formulae in homebrew/core should not use `build.with?`.
          end
        end
      RUBY
    end

    it "reports an offense when `build.without?` is used for a conditional dependency" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "bar" if build.without?("baz")
                              ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Use `:optional` or `:recommended` instead of `if build.without?("baz")`
        end
      RUBY
    end

    it "reports an offense when `build.with?` is used for a conditional dependency" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          depends_on "bar" if build.with?("baz")
                              ^^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Use `:optional` or `:recommended` instead of `if build.with?("baz")`
        end
      RUBY
    end

    it "reports an offense when `build.without?` is used with `unless`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def post_install
            return unless build.without? "bar"
                          ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Use if build.with? "bar" instead of unless build.without? "bar"
          end
        end
      RUBY
    end

    it "reports an offense when `build.with?` is used with `unless`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def post_install
            return unless build.with? "bar"
                          ^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Use if build.without? "bar" instead of unless build.with? "bar"
          end
        end
      RUBY
    end

    it "reports an offense when `build.with?` is negated" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def post_install
            return if !build.with? "bar"
                      ^^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Don't negate 'build.with?': use 'build.without?'
          end
        end
      RUBY
    end

    it "reports an offense when `build.without?` is negated" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def post_install
            return if !build.without? "bar"
                      ^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Don't negate 'build.without?': use 'build.with?'
          end
        end
      RUBY
    end

    it "reports an offense when a `build.without?` conditional is unnecessary" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def post_install
            return if build.without? "--without-bar"
                                     ^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Don't duplicate 'without': Use `build.without? "bar"` to check for "--without-bar"
          end
        end
      RUBY
    end

    it "reports an offense when a `build.with?` conditional is unnecessary" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def post_install
            return if build.with? "--with-bar"
                                  ^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Don't duplicate 'with': Use `build.with? "bar"` to check for "--with-bar"
          end
        end
      RUBY
    end

    it "reports an offense when `build.include?` is used" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'
          def post_install
            return if build.include? "foo"
                      ^^^^^^^^^^^^^^^^^^^^ FormulaAudit/OptionDeclarations: `build.include?` is deprecated
          end
        end
      RUBY
    end

    it "reports an offense when `def option` is used" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          desc "foo"
          url 'https://brew.sh/foo-1.0.tgz'

          def options
          ^^^^^^^^^^^ FormulaAudit/OptionDeclarations: Use new-style option definitions
            [["--bar", "desc"]]
          end
        end
      RUBY
    end
  end
end
