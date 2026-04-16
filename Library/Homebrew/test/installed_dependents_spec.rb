# typed: false
# frozen_string_literal: true

require "installed_dependents"

RSpec.describe InstalledDependents do
  include FileUtils

  def stub_formula(name, version = "1.0", &block)
    f = formula(name) do
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

  let!(:keg) { setup_test_keg("foo", "1.0") }
  let!(:keg_only_keg) do
    setup_test_keg("foo-keg-only", "1.0") do
      keg_only "a good reason"
    end
  end

  describe "::find_some_installed_dependents" do
    def setup_test_keg(name, version, &block)
      keg = super
      Tab.create(keg.to_formula, DevelopmentTools.default_compiler, :libcxx).write
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
        depends_on "foo"
        depends_on "baz"
      end

      # allow tap_dep to be linked too
      FileUtils.rm_r tap_dep/"bin"
      tap_dep.link

      alter_tab(keg) { |t| t.source["tap"] = nil }

      # nil tab means no known dependencies — don't fall back to formula definitions
      tab_dependencies dependent, nil

      result = described_class.find_some_installed_dependents([keg, tap_dep])
      expect(result).to be_nil
    end

    specify "no dependencies anywhere" do
      dependent = setup_test_keg("bar", "1.0")
      tab_dependencies dependent, nil
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    specify "nil tab does not fall back to formula definitions" do
      dependent = setup_test_keg("bar", "1.0") do
        depends_on "foo"
      end
      # Tab has nil runtime_dependencies — should not fall back to the
      # formula definition's depends_on, so uninstalling foo is allowed.
      tab_dependencies dependent, nil
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    specify "uninstalling dependent and dependency" do
      dependent = setup_test_keg("bar", "1.0") do
        depends_on "foo"
      end
      tab_dependencies dependent, nil
      expect(described_class.find_some_installed_dependents([keg, dependent])).to be_nil
    end

    specify "renamed dependency with nil tab" do
      dependent = setup_test_keg("bar", "1.0") do
        depends_on "foo"
      end
      # nil tab — no known dependencies, even though formula DSL says depends_on "foo"
      tab_dependencies dependent, nil

      stub_formula_loader Formula["foo"], "homebrew/core/foo-old"
      renamed_path = HOMEBREW_CELLAR/"foo-old"
      (HOMEBREW_CELLAR/"foo").rename(renamed_path)
      renamed_keg = Keg.new(renamed_path/keg.version.to_s)

      result = described_class.find_some_installed_dependents([renamed_keg])
      expect(result).to be_nil
    end

    specify "renamed dependency with tab data" do
      dependent = setup_test_keg("bar", "1.0") do
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

    specify "old tab version returns nil dependencies and does not block" do
      dependent = setup_test_keg("bar", "1.0") do
        depends_on "foo"
      end
      # Tab from Homebrew < 1.1.6 is unreliable; runtime_dependencies returns nil.
      # With tab-only trust, nil means no known deps — uninstall is allowed.
      unreliable_tab_dependencies dependent, [{ "full_name" => "baz", "version" => "1.0" }]
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
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
      c = Cask::CaskLoader.load(<<-RUBY)
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
        depends_on "foo"
      end
      tab_dependencies dependent, [{ "full_name" => "baz", "version" => "1.0" }]
      expect(described_class.find_some_installed_dependents([keg])).to be_nil
    end

    specify "tab with dependency blocks uninstall" do
      # Tab records that bar depends on foo — foo should block uninstall.
      dependent = setup_test_keg("bar", "1.0") do
        depends_on "foo"
      end
      tab_dependencies dependent, [{ "full_name" => "foo", "version" => "1.0" }]
      expect(described_class.find_some_installed_dependents([keg])).to eq([[keg], ["bar"]])
    end

    specify "identify dependent casks" do
      setup_test_cask("qux", "1.0.0", "foo")
      dependents = described_class.find_some_installed_dependents([keg]).last
      expect(dependents.include?("qux")).to be(true)
    end
  end
end
