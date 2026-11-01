# typed: true
# frozen_string_literal: true

require "dependency"

RSpec.describe Dependency do
  alias_matcher :be_a_build_dependency, :be_build

  describe "::new" do
    it "accepts a single tag" do
      dep = described_class.new("foo", %w[bar])
      expect(dep.tags).to eq(%w[bar])
    end

    it "accepts multiple tags" do
      dep = described_class.new("foo", %w[bar baz])
      expect(dep.tags.sort).to eq(%w[bar baz].sort)
    end

    it "preserves symbol tags" do
      dep = described_class.new("foo", [:build])
      expect(dep.tags).to eq([:build])
    end

    it "accepts symbol and string tags" do
      dep = described_class.new("foo", [:build, "bar"])
      expect(dep.tags).to eq([:build, "bar"])
    end
  end

  describe "::merge_repeats" do
    it "merges duplicate dependencies" do
      dep = described_class.new("foo", [:build])
      dep2 = described_class.new("foo", ["bar"])
      dep3 = described_class.new("xyz", ["abc"])
      merged = described_class.merge_repeats([dep, dep2, dep3])
      expect(merged.count).to eq(2)
      expect(merged.first).to be_a described_class
      expect(merged.to_h { |d| [d.name, d.tags] }).to eq("foo" => ["bar"], "xyz" => ["abc"])
    end

    it "merges necessity tags" do
      required_dep = described_class.new("foo")
      recommended_dep = described_class.new("foo", [:recommended])
      optional_dep = described_class.new("foo", [:optional])

      deps = described_class.merge_repeats([required_dep, recommended_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).to be_required
      expect(deps.first).not_to be_recommended
      expect(deps.first).not_to be_optional

      deps = described_class.merge_repeats([required_dep, optional_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).to be_required
      expect(deps.first).not_to be_recommended
      expect(deps.first).not_to be_optional

      deps = described_class.merge_repeats([recommended_dep, optional_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).not_to be_required
      expect(deps.first).to be_recommended
      expect(deps.first).not_to be_optional
    end

    it "merges temporality tags" do
      normal_dep = described_class.new("foo")
      build_dep = described_class.new("foo", [:build])

      deps = described_class.merge_repeats([normal_dep, build_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).not_to be_a_build_dependency
    end
  end

  specify "equality" do
    foo1 = described_class.new("foo")
    foo2 = described_class.new("foo")
    expect(foo1).to eq(foo2)
    expect(foo1).to eql(foo2)

    bar = described_class.new("bar")
    expect(foo1).not_to eq(bar)
    expect(foo1).not_to eql(bar)

    foo3 = described_class.new("foo", [:build])
    expect(foo1).not_to eq(foo3)
    expect(foo1).not_to eql(foo3)

    uses_from_macos_ventura = UsesFromMacOSDependency.new("foo", [], bounds: { since: :ventura })
    uses_from_macos_sonoma = UsesFromMacOSDependency.new("foo", [], bounds: { since: :sonoma })
    expect(uses_from_macos_ventura).not_to eq(uses_from_macos_sonoma)
    expect(uses_from_macos_ventura).not_to eql(uses_from_macos_sonoma)
  end

  describe "#tap" do
    it "returns a tap passed a fully-qualified name" do
      dependency = described_class.new("foo/bar/dog")
      expect(dependency.tap).to eq(Tap.fetch("foo", "bar"))
    end

    it "returns no tap passed a simple name" do
      dependency = described_class.new("dog")
      expect(dependency.tap).to be_nil
    end
  end

  describe "#formula_name?" do
    it "only accepts bare or tap-qualified formula names" do
      names = ["foo", "foo@1.2", "foo-bar+baz", "homebrew/core/foo", "user/repo/foo", ".", "..", "foo.rb",
               "user/repo/foo.rb", "foo--1.0.arm64_sequoia.bottle.tar.gz", "foo\n", "user/repo/foo\n",
               "/Cellar/foo/1.0/bar.rb", "../foo", "user/../foo", "file:///foo.rb"]
      expect(names.select { |name| described_class.new(name).formula_name? })
        .to eq(["foo", "foo@1.2", "foo-bar+baz", "homebrew/core/foo", "user/repo/foo"])
    end
  end

  describe "a formula file named by its path" do
    subject(:dependency) { described_class.new(formula_file.to_s) }

    let(:formula_file) { HOMEBREW_CELLAR/"foo/1.0/libexec/bar.rb" }
    let(:loaded) { formula_file.dirname/"loaded" }

    before do
      formula_file.dirname.mkpath
      formula_file.write "File.write(#{loaded.to_s.inspect}, \"\")\n"
    end

    specify "#installed? does not load it" do
      dependency.installed?
      expect(loaded).not_to exist
    end

    specify "#to_formula does not load it" do
      begin
        dependency.to_formula
      rescue FormulaUnavailableError
        nil
      end
      expect(loaded).not_to exist
    end
  end

  specify "#option_names" do
    dependency = described_class.new("foo/bar/dog")
    expect(dependency.option_names).to eq(%w[dog])
  end

  describe "with no_linkage tag" do
    it "marks dependency as no_linkage" do
      dep = described_class.new("foo", [:no_linkage])
      expect(dep).to be_no_linkage
      expect(dep).to be_required
      expect(dep).not_to be_build
      expect(dep).not_to be_test
    end
  end

  describe "Dependency#installed? with bottle_os_version" do
    subject(:dependency) { described_class.new("foo") }

    it "accepts macOS bottle_os_version parameter" do
      expect { dependency.installed?(bottle_os_version: "macOS 14") }.not_to raise_error
    end

    it "accepts Ubuntu bottle_os_version parameter" do
      expect { dependency.installed?(bottle_os_version: "Ubuntu 22.04") }.not_to raise_error
    end
  end

  describe "Dependency#installed? with minimum_compatibility_version" do
    subject(:dependency) { described_class.new("foo") }

    let(:keg) { instance_double(Keg, name: "foo") }

    before do
      allow(dependency).to receive(:to_installed_formula).and_return(
        instance_double(Formula, opt_prefix: instance_double(Pathname, exist?: true),
                                 latest_version_installed?: false, any_installed_keg: keg,
                                 possible_names: ["foo"], compatibility_version: 1),
      )
      allow(Tab).to receive(:for_keg).with(keg).and_return(
        instance_double(Tab, source: { "versions" => { "compatibility_version" => 1 } }),
      )
    end

    it "is true for an outdated keg with a matching compatibility_version" do
      expect(dependency.installed?(minimum_compatibility_version: 1)).to be(true)
    end

    it "is false for an outdated keg with a different compatibility_version" do
      expect(dependency.installed?(minimum_compatibility_version: 2)).to be(false)
    end
  end

  describe "Dependency#satisfied? with bottle_os_version" do
    subject(:dependency) { described_class.new("foo") }

    it "accepts bottle_os_version parameter" do
      expect { dependency.satisfied?(bottle_os_version: "macOS 14") }.not_to raise_error
    end

    it "accepts Ubuntu bottle_os_version parameter" do
      expect { dependency.installed?(bottle_os_version: "Ubuntu 22.04") }.not_to raise_error
    end
  end

  describe "UsesFromMacOSDependency#installed? with bottle_os_version" do
    subject(:uses_from_macos) { described_class.new("foo", bounds: { since: :sonoma }) }

    it "accepts macOS bottle_os_version parameter" do
      expect { uses_from_macos.installed?(bottle_os_version: "macOS 14") }.not_to raise_error
    end

    it "accepts Ubuntu bottle_os_version parameter" do
      expect { uses_from_macos.installed?(bottle_os_version: "Ubuntu 22.04") }.not_to raise_error
    end
  end
end
