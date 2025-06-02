# frozen_string_literal: true

require "rubocops/options"

RSpec.describe RuboCop::Cop::FormulaAudit::Options do
  subject(:cop) { described_class.new }

  context "when auditing options" do
    it "reports an offense when using the 32-bit option" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          option "with-32-bit"
                 ^^^^^^^^^^^^^ FormulaAudit/Options: macOS has been 64-bit only since 10.6 so 32-bit options are deprecated.
        end
      RUBY
    end

    it "reports an offense when using `:universal`" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          option :universal
          ^^^^^^^^^^^^^^^^^ FormulaAudit/Options: macOS has been 64-bit only since 10.6 so universal options are deprecated.
        end
      RUBY
    end

    it "reports an offense when using bad option names" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          option :cxx11
          option "examples", "with-examples"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Options: Options should begin with with/without. Migrate '--examples' with `deprecated_option`.
        end
      RUBY
    end

    it "reports an offense when using `without-check` option names" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          option "without-check"
          ^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Options: Use '--without-test' instead of '--without-check'. Migrate '--without-check' with `deprecated_option`.
        end
      RUBY
    end

    it "reports an offense when using `deprecated_option` in homebrew/core" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          deprecated_option "examples" => "with-examples"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Options: Formulae in homebrew/core should not use `deprecated_option`.
        end
      RUBY
    end

    it "reports an offense when using `option` in homebrew/core" do
      expect_offense(<<~RUBY, "/homebrew-core/")
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          option "with-examples"
          ^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Options: Formulae in homebrew/core should not use `option`.
        end
      RUBY
    end
  end
end
