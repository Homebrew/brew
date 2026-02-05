# frozen_string_literal: true

require "rubocops/options"

RSpec.describe RuboCop::Cop::FormulaAudit::Options do
  subject(:cop) { described_class.new }

  context "when auditing options" do
    it "reports an offense when using bad option names" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url 'https://brew.sh/foo-1.0.tgz'
          option "examples", "with-examples"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/Options: Options should begin with `with` or `without`. Migrate '--examples' with `deprecated_option`.
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
