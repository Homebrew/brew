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

    def install_formula(name, receipt_dependency: nil, outdated: false)
      f = formula(name) do
        T.bind(self, T.class_of(Formula))
        url(outdated ? "f-2" : "f-1")
      end
      prefix = f.rack/"1"
      prefix.mkpath
      Keg.new(prefix).optlink
      stub_formula_loader f
      return f if receipt_dependency.nil?

      tab = Tab.empty
      tab.homebrew_version = "1.1.6"
      tab.tabfile = prefix/AbstractTab::FILENAME
      tab.runtime_dependencies = [{ "full_name" => receipt_dependency, "version" => "1" }]
      tab.write
      f
    end

    specify "when upgrading outdated dependents stops them requiring the keg" do
      former_dependency = install_formula("former_dependency")
      install_formula("outdated_dependent", receipt_dependency: "former_dependency", outdated: true)
      install_formula("pinned_dependent", receipt_dependency: "former_dependency", outdated: true).pin
      kegs_by_rack = { former_dependency.rack => [Keg.new(former_dependency.latest_installed_prefix)] }

      expect { described_class.handle_unsatisfied_dependents(kegs_by_rack, named_args: ["former_dependency"]) }
        .to output(<<~EOS).to_stderr
          Error: Refusing to uninstall #{HOMEBREW_CELLAR}/former_dependency/1
          because it is required by outdated_dependent and pinned_dependent, which are currently installed.
          To stop the dependents below from requiring it, run:
            brew unpin pinned_dependent
            brew upgrade outdated_dependent pinned_dependent
          You can override this and force removal with:
            brew uninstall --ignore-dependencies former_dependency
        EOS
    end

    specify "when a cask requires the keg as well" do
      former_dependency = install_formula("former_dependency")
      install_formula("outdated_dependent", receipt_dependency: "former_dependency", outdated: true)
      keg = Keg.new(former_dependency.latest_installed_prefix)
      allow(InstalledDependents).to receive(:find_some_installed_dependents)
        .and_return([[keg], ["dependent_cask", "outdated_dependent"]])

      expect { described_class.handle_unsatisfied_dependents({ former_dependency.rack => [keg] }) }
        .not_to output(/brew upgrade/).to_stderr
    end

    specify "when a dependent requires the keg under another name" do
      former_dependency = install_formula("former_dependency")
      install_formula("outdated_dependent", receipt_dependency: "former_dependency", outdated: true)
      install_formula("other_dependent", receipt_dependency: "former_dependency_alias")
      keg = Keg.new(former_dependency.latest_installed_prefix)
      allow(InstalledDependents).to receive(:find_some_installed_dependents)
        .and_return([[keg], ["other_dependent", "outdated_dependent"]])

      expect { described_class.handle_unsatisfied_dependents({ former_dependency.rack => [keg] }) }
        .not_to output(/brew upgrade/).to_stderr
    end

    specify "when the only formula that still declares the keg is uninstalled as well" do
      install_formula("stale_dependent", receipt_dependency: "dependency")
      kegs_by_rack = [dependency, dependent_formula].to_h { |f| [f.rack, [Keg.new(f.latest_installed_prefix)]] }

      expect { described_class.handle_unsatisfied_dependents(kegs_by_rack) }.not_to output.to_stderr
    end

    specify "when `ignore_dependencies` is true" do
      expect do
        described_class.handle_unsatisfied_dependents(kegs_by_rack, ignore_dependencies: true)
      end.not_to output.to_stderr

      expect(Homebrew).not_to have_failed
    end
  end
end
