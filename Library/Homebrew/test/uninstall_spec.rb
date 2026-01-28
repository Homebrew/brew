# frozen_string_literal: true

require "uninstall"

RSpec.describe Homebrew::Uninstall do
  let(:dependency) { formula("dependency") { url "f-1" } }

  let(:dependent_formula) do
    formula("dependent_formula") do
      url "f-1"
      depends_on "dependency"
    end
  end

  let(:dependent_cask) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "dependent_cask" do
        version "1.0.0"

        url "c-1"
        depends_on formula: "dependency"
      end
    RUBY
  end

  let(:kegs_by_rack) { { dependency.rack => [Keg.new(dependency.latest_installed_prefix)] } }

  before do
    [dependency, dependent_formula].each do |f|
      f.latest_installed_prefix.mkpath
      Keg.new(f.latest_installed_prefix).optlink
    end

    tab = Tab.empty
    tab.homebrew_version = "1.1.6"
    tab.tabfile = dependent_formula.latest_installed_prefix/AbstractTab::FILENAME
    tab.runtime_dependencies = [
      { "full_name" => "dependency", "version" => "1" },
    ]
    tab.write

    Cask::Caskroom.path.join("dependent_cask", dependent_cask.version).mkpath

    stub_formula_loader dependency
    stub_formula_loader dependent_formula
    stub_cask_loader dependent_cask
  end

  describe "::handle_unsatisfied_dependents" do
    specify "when `ignore_dependencies` is false" do
      expect do
        described_class.handle_unsatisfied_dependents(kegs_by_rack)
      end.to output(/Error/).to_stderr

      expect(Homebrew).to have_failed
    end

    specify "when `ignore_dependencies` is true" do
      expect do
        described_class.handle_unsatisfied_dependents(kegs_by_rack, ignore_dependencies: true)
      end.not_to output.to_stderr

      expect(Homebrew).not_to have_failed
    end
  end
end
