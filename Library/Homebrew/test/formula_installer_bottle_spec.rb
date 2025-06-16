# frozen_string_literal: true

require "formula"
require "formula_installer"
require "keg"
require "tab"
require "cmd/install"
require "test/support/fixtures/testball"
require "test/support/fixtures/testball_bottle"
require "test/support/fixtures/testball_bottle_cellar"

RSpec.describe FormulaInstaller do
  alias_matcher :pour_bottle, :be_pour_bottle

  matcher :be_poured_from_bottle do
    match(&:poured_from_bottle)
  end

  def temporarily_install_bottle(formula)
    expect(formula).not_to be_latest_version_installed
    expect(formula).to be_bottled
    expect(formula).to pour_bottle

    stub_formula_loader formula("gcc") { url "gcc-1.0" }
    stub_formula_loader formula("glibc") { url "glibc-1.0" }
    stub_formula_loader formula

    fi = FormulaInstaller.new(formula)
    fi.fetch
    fi.install

    keg = Keg.new(formula.prefix)

    expect(formula).to be_latest_version_installed

    begin
      expect(keg.tab).to be_poured_from_bottle

      yield formula
    ensure
      keg.unlink
      keg.uninstall
      formula.clear_cache
      formula.bottle.clear_cache
    end

    expect(keg).not_to exist
    expect(formula).not_to be_latest_version_installed
  end

  def test_basic_formula_setup(formula)
    # Test that things made it into the Keg
    expect(formula.bin).to be_a_directory

    expect(formula.libexec).to be_a_directory

    expect(formula.prefix/"main.c").not_to exist

    # Test that things made it into the Cellar
    keg = Keg.new formula.prefix
    keg.link

    bin = HOMEBREW_PREFIX/"bin"
    expect(bin).to be_a_directory

    expect(formula.libexec).to be_a_directory
  end

  # This test wraps expect() calls in `test_basic_formula_setup`
  # rubocop:disable RSpec/NoExpectationExample
  specify "basic bottle install" do
    allow(DevelopmentTools).to receive(:installed?).and_return(false)
    Homebrew::Cmd::InstallCmd.new(["testball_bottle"])
    temporarily_install_bottle(TestballBottle.new) do |f|
      test_basic_formula_setup(f)
    end
  end
  # rubocop:enable RSpec/NoExpectationExample

  specify "basic bottle install with cellar information on sha256 line" do
    allow(DevelopmentTools).to receive(:installed?).and_return(false)
    Homebrew::Cmd::InstallCmd.new(["testball_bottle_cellar"])
    temporarily_install_bottle(TestballBottleCellar.new) do |f|
      test_basic_formula_setup(f)

      # skip_relocation is always false on Linux but can be true on macOS.
      # see: extend/os/linux/software_spec.rb
      skip_relocation = !OS.linux?

      expect(f.bottle_specification.skip_relocation?).to eq(skip_relocation)
    end
  end

  specify "build tools error" do
    allow(DevelopmentTools).to receive(:installed?).and_return(false)

    # Testball doesn't have a bottle block, so use it to test this behavior
    formula = Testball.new

    expect(formula).not_to be_latest_version_installed
    expect(formula).not_to be_bottled

    expect do
      described_class.new(formula).install
    end.to raise_error(UnbottledError)

    expect(formula).not_to be_latest_version_installed
  end
end
