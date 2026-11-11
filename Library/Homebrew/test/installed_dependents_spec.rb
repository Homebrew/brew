# typed: true
# frozen_string_literal: true

require "installed_dependents"

RSpec.describe InstalledDependents do
  let!(:keg) { setup_test_keg("foo", "1.0") }
  let!(:keg_only_keg) do
    setup_test_keg("foo-keg-only", "1.0") do
      T.bind(self, T.class_of(Formula))
      keg_only "a good reason"
    end
  end

  include FileUtils

  def stub_formula(name, version = "1.0", &block)
    f = formula(name) do
      T.bind(self, T.class_of(Formula))
      url "#{name}-#{version}"

      instance_eval(&block) if block
    end
    stub_formula_loader f
    stub_formula_loader f, "homebrew/core/#{f}"
    f
  end

  def setup_test_keg(name, version, &block)
    stub_formula("gcc")
    stub_formula("glibc")
    stub_formula(name, version, &block)

    path = HOMEBREW_CELLAR/name/version
    (path/"bin").mkpath

    %w[hiworld helloworld goodbye_cruel_world].each do |file|
      touch path/"bin"/file
    end

    Keg.new(path)
  end

  describe "::find_some_installed_dependents" do
    def setup_test_keg(name, version, &block)
      keg = super
      tab = Tab.new(
        homebrew_version:         HOMEBREW_VERSION,
        installed_on_request:     false,
        loaded_from_api:          false,
        loaded_from_internal_api: false,
        source:                   {
          "path"         => nil,
          "tap"          => "homebrew/core",
          "tap_git_head" => nil,
          "spec"         => "stable",
          "versions"     => {
            "stable"                => version,
            "head"                  => nil,
            "version_scheme"        => 0,
            "compatibility_version" => nil,
          },
        },
        built_on:                 {},
      )
      tab.tabfile = keg/AbstractTab::FILENAME
      tab.stdlib = :libcxx
      tab.compiler = DevelopmentTools.default_compiler
      tab.aliases = []
      tab.runtime_dependencies = []
      tab.write
      keg
    end

    before do
      keg.link
      keg_only_keg.optlink
    end

    def alter_tab(keg)
      tab = keg.tab
      yield tab
      tab.write
    end

    # 1.1.6 is the earliest version of Homebrew that generates correct runtime
    # dependency lists in {Tab}s.
    def tab_dependencies(keg, deps, homebrew_version: "1.1.6")
      alter_tab(keg) do |tab|
        tab.homebrew_version = homebrew_version
        tab.tabfile = keg/AbstractTab::FILENAME
        tab.runtime_dependencies = deps
      end
    end

    def unreliable_tab_dependencies(keg, deps)
      # 1.1.5 is (hopefully!) the last version of Homebrew that generates
      # incorrect runtime dependency lists in {Tab}s.
      tab_dependencies(keg, deps, homebrew_version: "1.1.5")
    end

    specify "a dependency with no Tap in Tab" do
      tap_dep = setup_test_keg("baz", "1.0")
      dependent = setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
        depends_on "baz"
      end

      # allow tap_dep to be linked too
      FileUtils.rm_r tap_dep/"bin"
      tap_dep.link

      alter_tab(keg) { |t| t.source["tap"] = nil }

      tab_dependencies dependent, nil

      result = described_class.find_some_installed_dependents([keg, tap_dep])
      expect(result).to eq([[keg, tap_dep], ["bar"]])
    end

    specify "no dependencies anywhere" do
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, nil
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    specify "nil tab falls back to formula definitions" do
      dependent = setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      tab_dependencies dependent, nil
      expect(described_class.find_some_installed_dependents([keg])).to eq([[keg], ["bar"]])
    end

    specify "untrusted dependencies that match a keg being removed" do
      dependent = setup_test_keg("bar", "1.0")
      dependent_formula = dependent.to_formula
      dependency = Dependency.new("untrusted/tap/dependency")
      allow(dependent_formula).to receive(:missing_dependencies).and_return([dependency])
      allow(dependency).to receive(:to_installed_formula).and_raise(Homebrew::UntrustedTapError)

      untrusted_tap = Tap.fetch("untrusted/tap")
      loader = instance_double(Formulary::FormulaLoader, name: "dependency", tap: untrusted_tap)
      allow(Formulary).to receive(:loader_for).and_call_original
      allow(Formulary).to receive(:loader_for).with("untrusted/tap/dependency", warn: false).and_return(loader)

      untrusted_keg = setup_test_keg("dependency", "1.0")
      alter_tab(untrusted_keg) { |tab| tab.tap = untrusted_tap }
      allow(untrusted_keg).to receive(:to_formula).and_raise(Homebrew::UntrustedTapError)
      untrusted_keg.optlink

      result = described_class.find_some_installed_dependents([untrusted_keg], formulae: [dependent_formula])
      expect(result).to eq([[untrusted_keg], ["bar"]])
    end

    specify "unqualified untrusted dependencies match a keg being removed" do
      dependent = setup_test_keg("bar", "1.0")
      dependent_formula = dependent.to_formula
      dependency = Dependency.new("dependency")
      allow(dependent_formula).to receive(:missing_dependencies).and_return([dependency])
      allow(dependency).to receive(:to_installed_formula).and_raise(Homebrew::UntrustedTapError)

      untrusted_tap = Tap.fetch("untrusted/tap")
      untrusted_keg = setup_test_keg("dependency", "1.0")
      alter_tab(untrusted_keg) { |tab| tab.tap = untrusted_tap }
      allow(untrusted_keg).to receive(:to_formula).and_raise(Homebrew::UntrustedTapError)
      untrusted_keg.optlink
      loader = instance_double(Formulary::FormulaLoader, name: "dependency", tap: untrusted_tap)
      allow(Formulary).to receive(:loader_for).and_call_original
      allow(Formulary).to receive(:loader_for).with("dependency", warn: false).and_return(loader)

      result = described_class.find_some_installed_dependents([untrusted_keg], formulae: [dependent_formula])
      expect(result).to eq([[untrusted_keg], ["bar"]])
    end

    specify "renamed untrusted dependencies match the destination keg being removed" do
      dependent = setup_test_keg("bar", "1.0")
      dependent_formula = dependent.to_formula
      dependency = Dependency.new("untrusted/tap/old")
      allow(dependent_formula).to receive(:missing_dependencies).and_return([dependency])
      allow(dependency).to receive(:to_installed_formula).and_raise(Homebrew::UntrustedTapError)

      untrusted_tap = Tap.fetch("untrusted/tap")
      loader = instance_double(Formulary::FormulaLoader, name: "new", tap: untrusted_tap)
      allow(Formulary).to receive(:loader_for).and_call_original
      allow(Formulary).to receive(:loader_for).with("untrusted/tap/old", warn: false).and_return(loader)

      renamed_keg = setup_test_keg("new", "1.0")
      alter_tab(renamed_keg) { |tab| tab.tap = untrusted_tap }
      allow(renamed_keg).to receive(:to_formula).and_raise(Homebrew::UntrustedTapError)
      renamed_keg.optlink

      result = described_class.find_some_installed_dependents([renamed_keg], formulae: [dependent_formula])
      expect(result).to eq([[renamed_keg], ["bar"]])
    end

    specify "ambiguous unqualified untrusted dependencies match all possible kegs" do
      dependent = setup_test_keg("bar", "1.0")
      dependent_formula = dependent.to_formula
      dependency = Dependency.new("dependency")
      allow(dependent_formula).to receive(:missing_dependencies).and_return([dependency])

      first_tap = Tap.fetch("untrusted/first")
      second_tap = Tap.fetch("untrusted/second")
      loaders = [
        instance_double(Formulary::FormulaLoader, name: "dependency", tap: first_tap),
        instance_double(Formulary::FormulaLoader, name: "dependency", tap: second_tap),
      ]
      allow(Formulary).to receive(:loader_for).and_call_original
      allow(Formulary).to receive(:loader_for).with("dependency", any_args)
                                              .and_raise(TapFormulaAmbiguityError.new("dependency", loaders))

      first_keg = setup_test_keg("dependency-first", "1.0")
      second_keg = setup_test_keg("dependency-second", "1.0")
      [first_keg, second_keg].zip([first_tap, second_tap]).each do |candidate, tap|
        allow(candidate).to receive_messages(name: "dependency", optlinked?: true)
        allow(candidate).to receive(:to_formula).and_raise(Homebrew::UntrustedTapError)
        alter_tab(candidate) { |tab| tab.tap = tap }
      end

      result = described_class.find_some_installed_dependents([first_keg, second_keg], formulae: [dependent_formula])
      expect(result).to eq([[first_keg, second_keg], ["bar"]])
    end

    specify "does not match an untrusted dependency to a keg from another tap" do
      dependent = setup_test_keg("bar", "1.0")
      dependent_formula = dependent.to_formula
      dependency = Dependency.new("untrusted/first/dependency")
      allow(dependent_formula).to receive(:missing_dependencies).and_return([dependency])
      allow(dependency).to receive(:to_installed_formula).and_raise(Homebrew::UntrustedTapError)

      first_tap = Tap.fetch("untrusted/first")
      second_tap = Tap.fetch("untrusted/second")
      loader = instance_double(Formulary::FormulaLoader, name: "dependency", tap: first_tap)
      allow(Formulary).to receive(:loader_for).and_call_original
      allow(Formulary).to receive(:loader_for).with("untrusted/first/dependency", warn: false)
                                              .and_return(loader)

      other_keg = setup_test_keg("dependency", "1.0")
      alter_tab(other_keg) { |tab| tab.tap = second_tap }
      allow(other_keg).to receive(:to_formula).and_raise(Homebrew::UntrustedTapError)
      other_keg.optlink

      expect(described_class.find_some_installed_dependents([other_keg], formulae: [dependent_formula])).to be_nil
    end

    specify "uninstalling dependent and dependency" do
      dependent = setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      tab_dependencies dependent, nil
      expect(described_class.find_some_installed_dependents([keg, dependent])).to be_nil
    end

    specify "projected formula and cask removals do not block uninstall" do
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, [{ "full_name" => keg.name, "version" => keg.version.to_s }]
      cask = setup_test_cask("qux", "1.0.0", "foo")

      expect(described_class.find_some_installed_dependents([keg], formulae: [], casks: [cask])).to be_nil
    end

    specify "renamed dependency with nil tab" do
      dependent = setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      tab_dependencies dependent, nil

      stub_formula_loader Formula["foo"], "homebrew/core/foo-old"
      renamed_path = HOMEBREW_CELLAR/"foo-old"
      (HOMEBREW_CELLAR/"foo").rename(renamed_path)
      renamed_keg = Keg.new(renamed_path/keg.version.to_s)

      result = described_class.find_some_installed_dependents([renamed_keg])
      expect(result).to eq([[renamed_keg], ["bar"]])
    end

    specify "renamed dependency with tab data" do
      dependent = setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      tab_dependencies dependent, [{ "full_name" => "foo", "version" => "1.0" }]

      stub_formula_loader Formula["foo"], "homebrew/core/foo-old"
      renamed_path = HOMEBREW_CELLAR/"foo-old"
      (HOMEBREW_CELLAR/"foo").rename(renamed_path)
      renamed_keg = Keg.new(renamed_path/keg.version.to_s)

      result = described_class.find_some_installed_dependents([renamed_keg])
      expect(result).to eq([[renamed_keg], ["bar"]])
    end

    specify "empty dependencies in Tab" do
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, []
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    specify "same name but different version in Tab" do
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, [{ "full_name" => keg.name, "version" => "1.1" }]
      expect(described_class.find_some_installed_dependents([keg])).to eq([[keg], ["bar"]])
    end

    specify "different name and same version in Tab" do
      stub_formula("baz")
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, [{ "full_name" => "baz", "version" => keg.version.to_s }]
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    specify "same name and version in Tab" do
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, [{ "full_name" => keg.name, "version" => keg.version.to_s }]
      expect(described_class.find_some_installed_dependents([keg])).to eq([[keg], ["bar"]])
    end

    specify "old tab version falls back to formula definitions" do
      dependent = setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      unreliable_tab_dependencies dependent, [{ "full_name" => "baz", "version" => "1.0" }]
      expect(described_class.find_some_installed_dependents([keg])).to eq([[keg], ["bar"]])
    end

    specify "non-opt-linked" do
      keg.remove_opt_record
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, [{ "full_name" => keg.name, "version" => keg.version.to_s }]
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    specify "keg-only" do
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, [{ "full_name" => keg_only_keg.name, "version" => "1.1" }] # different version
      expect(described_class.find_some_installed_dependents([keg_only_keg])).to eq([[keg_only_keg], ["bar"]])
    end

    def stub_cask_name(name, version, dependency)
      c = Cask::CaskLoader.from_content(<<-RUBY)
        cask "#{name}" do
          version "#{version}"

          url "c-1"
          depends_on formula: "#{dependency}"
        end
      RUBY

      stub_cask_loader c
      c
    end

    def setup_test_cask(name, version, dependency)
      c = stub_cask_name(name, version, dependency)
      Cask::Caskroom.path.join(name, c.version).mkpath
      Cask::Caskroom.path.join(name, ".metadata", c.version, "0", "Casks").tap(&:mkpath)
                    .join("#{name}.rb").open("w") do |caskfile|
                      caskfile.puts <<~RUBY
                        cask "#{name}" do
                          version "#{version}"
                        end
                      RUBY
                    end
      c
    end

    specify "stale tab without dependency does not block uninstall" do
      # Formula definition says bar depends on foo, but the tab only
      # records baz — foo should not block uninstall because we trust
      # the tab over the formula definition.
      stub_formula("baz")
      dependent = setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      tab_dependencies dependent, [{ "full_name" => "baz", "version" => "1.0" }]
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    specify "tab with dependency blocks uninstall" do
      # Tab records that bar depends on foo — foo should block uninstall.
      dependent = setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      tab_dependencies dependent, [{ "full_name" => "foo", "version" => "1.0" }]
      expect(described_class.find_some_installed_dependents([keg])).to eq([[keg], ["bar"]])
    end

    specify "identify dependent casks" do
      setup_test_cask("qux", "1.0.0", "foo")

      expect(described_class.find_some_installed_dependents([keg])&.last).to include("qux")
    end
  end
end
