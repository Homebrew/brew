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
      Cask::Caskroom.path
                    .join(name, ".metadata", c.version, "0", "Casks")
                    .tap(&:mkpath)
                    .join("#{name}.rb")
                    .open("w") do |caskfile|
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

    specify "identify dependent casks when another cask depends on an unavailable formula" do
      allow(Formulary).to receive(:loader_for).with("unavailable", any_args).and_call_original
      setup_test_cask("quux", "1.0.0", "unavailable")
      setup_test_cask("qux", "1.0.0", "foo")

      expect(described_class.find_some_installed_dependents([keg])&.last).to eq(["qux"])
    end

    test_each([FormulaUnavailableError, Homebrew::UntrustedTapError]) do |error|
      specify "identify dependent casks of an installed formula that raises #{error}" do
        allow(Formulary).to receive(:loader_for).with("homebrew/core/foo", any_args)
                                                .and_raise(error.new("homebrew/core/foo"))
        allow(keg).to receive(:to_formula).and_raise(error.new("foo"))
        setup_test_cask("qux", "1.0.0", "homebrew/core/foo")

        expect(described_class.find_some_installed_dependents([keg])&.last).to eq(["qux"])
      end
    end
  end

  describe "::find_installed_build_dependents" do
    let!(:dependent) do
      setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo" => :build
      end
    end

    before { keg.optlink }

    specify "a formula built from source needs the keg to build" do
      expect(described_class.find_installed_build_dependents([keg])).to eq([[keg], ["bar"]])
    end

    def pour_from_usable_bottle(*poured_kegs)
      poured_kegs.each do |poured_keg|
        tab = Tab.empty
        tab.tabfile = poured_keg/AbstractTab::FILENAME
        tab.poured_from_bottle = true
        tab.write
      end
      allow(Formulary.factory("bar")).to receive_messages(bottled?: true, pour_bottle?: true)
    end

    specify "a formula poured from a usable bottle doesn't need the keg to build" do
      pour_from_usable_bottle(keg, dependent)

      expect(described_class.find_installed_build_dependents([keg])).to be_nil
    end

    specify "a formula whose remaining keg was built from source still needs the keg to build" do
      linked_dependent = Keg.new((dependent.rack/"2.0").tap(&:mkpath))
      linked_dependent.optlink
      pour_from_usable_bottle(keg, linked_dependent)

      expect(described_class.find_installed_build_dependents([keg, linked_dependent])).to eq([[keg], ["bar"]])
    end

    specify "a formula that is uninstalled too doesn't need the keg to build" do
      expect(described_class.find_installed_build_dependents([keg, dependent])).to be_nil
    end

    specify "a formula that keeps another keg still needs the keg to build" do
      (dependent.rack/"2.0").mkpath

      expect(described_class.find_installed_build_dependents([keg, dependent])).to eq([[keg], ["bar"]])
    end

    specify "an older keg isn't needed to build while the linked one stays" do
      older_keg = Keg.new((keg.rack/"0.9").tap(&:mkpath))

      expect(described_class.find_installed_build_dependents([older_keg])).to be_nil
    end

    specify "the last keg is needed to build even when `opt` doesn't point to it" do
      keg.remove_opt_record

      expect(described_class.find_installed_build_dependents([keg])).to eq([[keg], ["bar"]])
    end

    specify "a keg whose formula has no usable spec is still needed to build" do
      allow(keg).to receive(:to_formula).and_raise(FormulaSpecificationError)

      expect(described_class.find_installed_build_dependents([keg])).to eq([[keg], ["bar"]])
    end

    specify "the kegs of a formula that isn't uninstalled aren't listed" do
      expect(Formulary.factory("bar")).not_to receive(:installed_kegs)

      described_class.find_installed_build_dependents([keg])
    end
  end

  describe "::build_dependents_by_name" do
    let(:installed) { Formula.installed }

    before do
      setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo" => :build
      end
    end

    it "maps the build dependencies to keep to the formulae that need them" do
      expect(described_class.build_dependents_by_name(installed, installed)).to eq("foo" => ["bar"])
    end

    it "looks up a build dependency once for all the formulae that need it" do
      setup_test_keg("baz", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo" => :build
      end
      formulae = installed
      allow(Formulary).to receive(:factory).and_call_original
      expect(Formulary).to receive(:factory).with("foo", warn: false).once.and_call_original

      described_class.build_dependents_by_name(formulae, formulae)
    end

    it "keeps a build dependency whose tap is untrusted" do
      build_dependency = installed.flat_map { |f| f.deps.to_a }.find(&:build?)
      allow(build_dependency).to receive(:to_formula).and_raise(Homebrew::UntrustedTapError)

      expect(described_class.build_dependents_by_name(installed, installed)).to eq("foo" => ["bar"])
    end

    it "keeps a build dependency whose formula has no usable spec" do
      build_dependency = installed.flat_map { |f| f.deps.to_a }.find(&:build?)
      allow(build_dependency).to receive(:to_formula).and_raise(FormulaSpecificationError)

      expect(described_class.build_dependents_by_name(installed, installed)).to eq("foo" => ["bar"])
    end
  end

  describe "::formulae_safe_to_remove" do
    let(:installed) { Formula.installed }

    before do
      setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
        depends_on "foo-keg-only" => :build
      end
    end

    it "removes formulae when everything that depends on them is also being removed" do
      expect(described_class.formulae_safe_to_remove(installed, installed)).to match_array(installed)
    end

    it "keeps runtime and build dependencies of formulae that stay installed" do
      expect(described_class.formulae_safe_to_remove(installed - [Formulary.factory("bar")], installed)).to eq([])
    end

    it "keeps dependencies of formulae that it has decided to keep" do
      setup_test_keg("baz", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "bar"
      end

      expect(described_class.formulae_safe_to_remove(installed - [Formulary.factory("baz")], installed)).to eq([])
    end
  end

  describe "::commands_to_drop_dependencies" do
    let(:dependency) { instance_double(Dependency, name: "foo") }

    def commands_for_dependent(outdated: true, others: [])
      dependent = instance_double(Formula, full_name: "bar", outdated?: outdated, pinned?: false, disabled?: false,
                                           runtime_dependencies: [dependency])
      allow(dependent).to receive(:runtime_dependencies).with(read_from_tab: false, undeclared: false).and_return([])
      yield dependent if block_given?

      described_class.commands_to_drop_dependencies({ "foo" => "foo" }, [dependent, *others])
    end

    it "upgrades an outdated dependent whose latest version no longer declares the dependency" do
      expect(commands_for_dependent).to eq(["brew upgrade bar"])
    end

    it "unpins a pinned outdated dependent before upgrading it" do
      commands = commands_for_dependent { |dependent| allow(dependent).to receive(:pinned?).and_return(true) }

      expect(commands).to eq(["brew unpin bar", "brew upgrade bar"])
    end

    it "leaves an up-to-date dependent to the pruning of its install receipt" do
      expect(commands_for_dependent(outdated: false)).to eq([])
    end

    it "skips a disabled dependent, which cannot be upgraded" do
      commands = commands_for_dependent { |dependent| allow(dependent).to receive(:disabled?).and_return(true) }

      expect(commands).to eq([])
    end

    it "skips a dependent with a dependency from an untrusted tap" do
      commands = commands_for_dependent do |dependent|
        allow(dependent).to receive(:runtime_dependencies).with(read_from_tab: false, undeclared: false)
                                                          .and_raise(Homebrew::UntrustedTapError)
      end

      expect(commands).to eq([])
    end

    it "suggests nothing while another dependent still declares the dependency" do
      other = instance_double(Formula, full_name: "baz", outdated?: false, pinned?: false,
                                       runtime_dependencies: [dependency])

      expect(commands_for_dependent(others: [other])).to eq([])
    end

    it "suggests nothing while a dependent without a receipt list has a dependency from an untrusted tap" do
      other = instance_double(Formula, full_name: "baz")
      allow(other).to receive(:runtime_dependencies).and_raise(Homebrew::UntrustedTapError)
      allow(other).to receive(:runtime_dependencies).with(stop_at_untrusted: true).and_return([dependency])

      expect(commands_for_dependent(others: [other])).to eq([])
    end

    it "suggests nothing while a dependent with a dependency from an untrusted tap lists the dependency" do
      other = instance_double(Formula, full_name: "baz", runtime_dependencies: [dependency])
      allow(other).to receive(:runtime_dependencies).with(read_from_tab: false, undeclared: false)
                                                    .and_raise(Homebrew::UntrustedTapError)

      expect(commands_for_dependent(others: [other])).to eq([])
    end
  end

  describe "::prune_stale_dependencies" do
    let(:dependent_keg) do
      setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "baz"
      end
    end
    let(:dependent) { Formulary.factory("bar") }
    let(:receipt_dependencies) do
      JSON.parse((dependent_keg/AbstractTab::FILENAME).read).fetch("runtime_dependencies").map { it["full_name"] }
    end

    def write_receipt(keg, *dependencies)
      tab = Tab.empty
      tab.tabfile = keg/AbstractTab::FILENAME
      tab.runtime_dependencies = dependencies.map { |full_name| { "full_name" => full_name } }
      tab.write
    end

    before do
      keg.optlink
      write_receipt(setup_test_keg("baz", "1.0"))
      # `foo` was a dependency of `baz` when `bar` was installed.
      write_receipt(dependent_keg, "baz", "foo")
    end

    it "removes a dependency that the dependent's dependency tree no longer declares" do
      described_class.prune_stale_dependencies(Formula.installed)

      expect(receipt_dependencies).to eq(["baz"])
    end

    it "stops counting the dependent without writing its receipt in a dry run" do
      described_class.prune_stale_dependencies(Formula.installed, dry_run: true)
      dependents = described_class.find_some_installed_dependents([keg])

      expect([dependents, receipt_dependencies]).to eq([nil, ["baz", "foo"]])
    end

    it "stops counting a dependent whose dependencies were read before" do
      described_class.find_some_installed_dependents([keg])
      described_class.prune_stale_dependencies(Formula.installed, dry_run: true)

      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    it "skips the dependency tree when one of the dependent's dependencies declares the dependency" do
      setup_test_keg("baz", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      expect(dependent).not_to receive(:recursive_dependencies)

      described_class.prune_stale_dependencies([dependent, Formulary.factory("baz")])
    end

    it "keeps a dependency that the receipt lists under the name it had before it was renamed" do
      setup_test_keg("baz", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      allow(Formulary.factory("foo")).to receive(:possible_names).and_return(%w[foo foo-old])
      (HOMEBREW_PREFIX/"opt/foo-old").make_relative_symlink(HOMEBREW_CELLAR/"foo/1.0")
      write_receipt(dependent_keg, "baz", "foo-old")
      described_class.prune_stale_dependencies(Formula.installed)

      expect(receipt_dependencies).to eq(["baz", "foo-old"])
    end

    it "keeps a dependency that the dependent's keg links to" do
      allow(dependent).to receive(:runtime_dependencies).with(read_from_tab: false)
                                                        .and_return([Dependency.new("foo")])
      described_class.prune_stale_dependencies([dependent])

      expect(receipt_dependencies).to eq(["baz", "foo"])
    end

    it "keeps a dependency that is not installed" do
      keg.remove_opt_record
      described_class.prune_stale_dependencies(Formula.installed)

      expect(receipt_dependencies).to eq(["baz", "foo"])
    end

    it "keeps a dependency that another installed formula still declares" do
      other_keg = setup_test_keg("qux", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "foo"
      end
      write_receipt(other_keg, "foo")
      described_class.prune_stale_dependencies(Formula.installed)

      expect(receipt_dependencies).to eq(["baz", "foo"])
    end

    it "keeps the receipt of a dependent that is not the latest version" do
      allow(dependent).to receive(:pkg_version).and_return(PkgVersion.parse("1.1"))
      described_class.prune_stale_dependencies([dependent])

      expect(receipt_dependencies).to eq(["baz", "foo"])
    end

    it "keeps the receipt of a dependent that declares a dependency through an alias" do
      stub_formula_loader Formulary.factory("baz"), "baz-alias"
      setup_test_keg("bar", "1.0") do
        T.bind(self, T.class_of(Formula))
        depends_on "baz-alias"
      end
      described_class.prune_stale_dependencies(Formula.installed)

      expect(receipt_dependencies).to eq(["baz", "foo"])
    end

    it "keeps the receipt of a dependent whose dependency tree cannot be loaded" do
      allow(dependent).to receive(:recursive_dependencies).and_raise(FormulaUnavailableError.new("baz"))
      described_class.prune_stale_dependencies([dependent])

      expect(receipt_dependencies).to eq(["baz", "foo"])
    end
  end
end
