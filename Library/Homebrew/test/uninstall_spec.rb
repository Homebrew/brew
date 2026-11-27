# typed: true
# frozen_string_literal: true

require "uninstall"

RSpec.describe Homebrew::Uninstall do
  let(:dependency) do
    formula("dependency") do
      T.bind(self, T.class_of(Formula))
      url "f-1"
    end
  end

  let(:dependent_formula) do
    formula("dependent_formula") do
      T.bind(self, T.class_of(Formula))
      url "f-1"
      depends_on "dependency"
    end
  end

  let(:dependent_cask) do
    Cask::CaskLoader.from_content(+<<-RUBY)
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

  describe "::uninstall_kegs" do
    let(:kegs_by_rack) do
      [dependency, dependent_formula].to_h { |f| [f.rack, [Keg.new(f.latest_installed_prefix)]] }
    end

    before do
      allow(Formulary).to receive(:from_rack).with(dependency.rack).and_return(dependency)
      allow(Formulary).to receive(:from_rack).with(dependent_formula.rack).and_return(dependent_formula)
      allow(dependent_formula).to receive(:pinned?).and_return(true)
    end

    it "keeps a pinned formula" do
      expect { described_class.uninstall_kegs(kegs_by_rack) }
        .not_to change { dependent_formula.latest_installed_prefix.exist? }.from(true)
    end

    it "still uninstalls the other formulae" do
      expect { described_class.uninstall_kegs(kegs_by_rack) }
        .to change { dependency.latest_installed_prefix.exist? }.from(true).to(false)
    end
  end

  describe "::handle_unsatisfied_dependents" do
    specify "when `ignore_dependencies` is false" do
      expect do
        described_class.handle_unsatisfied_dependents(kegs_by_rack)
      end.to output(/Error/).to_stderr

      expect(Homebrew).to have_failed
    end

    specify "when a formula built from source needs the keg to build" do
      build_dependency = formula("build_dependency") do
        T.bind(self, T.class_of(Formula))
        url "f-1"
      end
      build_dependent = formula("build_dependent") do
        T.bind(self, T.class_of(Formula))
        url "f-1"
        depends_on "build_dependency" => :build
      end
      [build_dependency, build_dependent].each do |f|
        f.latest_installed_prefix.mkpath
        Keg.new(f.latest_installed_prefix).optlink
        stub_formula_loader f
      end
      kegs_by_rack = { build_dependency.rack => [Keg.new(build_dependency.latest_installed_prefix)] }

      expect { described_class.handle_unsatisfied_dependents(kegs_by_rack) }
        .to output(/required to build build_dependent, which is currently installed/).to_stderr
    end

    specify "when reinstalling an up-to-date dependent stops it requiring the keg" do
      stale_dependent = formula("stale_dependent") do
        T.bind(self, T.class_of(Formula))
        url "f-1"
      end
      stale_dependent.latest_installed_prefix.mkpath
      Keg.new(stale_dependent.latest_installed_prefix).optlink
      tab = Tab.empty
      tab.homebrew_version = "1.1.6"
      tab.tabfile = stale_dependent.latest_installed_prefix/AbstractTab::FILENAME
      tab.runtime_dependencies = [{ "full_name" => "dependency", "version" => "1" }]
      tab.write
      stub_formula_loader stale_dependent

      expect { described_class.handle_unsatisfied_dependents(kegs_by_rack, named_args: ["dependency"]) }
        .to output(<<~EOS).to_stderr
          Error: Refusing to uninstall #{HOMEBREW_CELLAR}/dependency/1
          because it is required by dependent_formula and stale_dependent, which are currently installed.
          To stop the dependents below from requiring it, run:
            brew reinstall stale_dependent
          You can override this and force removal with:
            brew uninstall --ignore-dependencies dependency
        EOS
    end

    specify "when `ignore_dependencies` is true" do
      expect do
        described_class.handle_unsatisfied_dependents(kegs_by_rack, ignore_dependencies: true)
      end.not_to output.to_stderr

      expect(Homebrew).not_to have_failed
    end
  end
end
