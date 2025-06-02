# frozen_string_literal: true

require "rubocops/uses_from_macos"

RSpec.describe RuboCop::Cop::FormulaAudit::UsesFromMacos do
  subject(:cop) { described_class.new }

  context "when auditing `uses_from_macos` dependencies" do
    it "reports an offense when used on non-macOS dependency" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          uses_from_macos "postgresql"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should only be used for macOS dependencies, not postgresql.
        end
      RUBY
    end

    it "reports offenses for multiple non-macOS dependencies and none for valid macOS dependencies" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          uses_from_macos "boost"
          ^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should only be used for macOS dependencies, not boost.
          uses_from_macos "bzip2"
          uses_from_macos "postgresql"
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should only be used for macOS dependencies, not postgresql.
          uses_from_macos "zlib"
        end
      RUBY
    end

    it "reports an offense when used in `depends_on :linux` formula" do
      expect_offense(<<~RUBY)
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tgz"
          homepage "https://brew.sh"

          depends_on :linux
          uses_from_macos "zlib"
          ^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/UsesFromMacos: `uses_from_macos` should not be used when Linux is required.
        end
      RUBY
    end
  end

  include_examples "formulae exist", described_class::ALLOWED_USES_FROM_MACOS_DEPS
end
