# frozen_string_literal: true

require "rubocops/uses_from_macos"

describe RuboCop::Cop::FormulaAudit::ProvidedByMacos do
  subject(:cop) { described_class.new }

  it "fails for formulae not in PROVIDED_BY_MACOS_FORMULAE list" do
    expect_offense(<<~RUBY)
      class Baz < Formula
        url "https://brew.sh/baz-1.0.tgz"
        homepage "https://brew.sh"

        keg_only :provided_by_macos
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ FormulaAudit/ProvidedByMacos: Formulae that are `keg_only :provided_by_macos` should be added to the `PROVIDED_BY_MACOS_FORMULAE` list (in the Homebrew/brew repo)
      end
    RUBY
  end

  it "succeeds for formulae in PROVIDED_BY_MACOS_FORMULAE list" do
    expect_no_offenses(<<~RUBY, "/homebrew-core/Formula/apr.rb")
      class Apr < Formula
        url "https://brew.sh/apr-1.0.tgz"
        homepage "https://brew.sh"

        keg_only :provided_by_macos
      end
    RUBY
  end

  it "succeeds for formulae that are keg_only for a different reason" do
    expect_no_offenses(<<~RUBY)
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tgz"
        homepage "https://brew.sh"

        keg_only :versioned_formula
      end
    RUBY
  end

  include_examples "formulae exist", described_class::PROVIDED_BY_MACOS_FORMULAE
end
