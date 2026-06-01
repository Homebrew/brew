# typed: true
# frozen_string_literal: true

require "dependency"

RSpec.describe Dependency do
  let(:klass) { Dependency }

  alias_matcher :be_a_build_dependency, :be_build

  describe "::new" do
    it "accepts a single tag" do
      dep = klass.new("foo", %w[bar])
      expect(dep.tags).to eq(%w[bar])
    end

    it "accepts multiple tags" do
      dep = klass.new("foo", %w[bar baz])
      expect(dep.tags.sort).to eq(%w[bar baz].sort)
    end

    it "preserves symbol tags" do
      dep = klass.new("foo", [:build])
      expect(dep.tags).to eq([:build])
    end

    it "accepts symbol and string tags" do
      dep = klass.new("foo", [:build, "bar"])
      expect(dep.tags).to eq([:build, "bar"])
    end

    it "rejects nil names" do
      expect { klass.new(nil) }.to raise_error(TypeError)
    end
  end

  describe "::merge_repeats" do
    it "merges duplicate dependencies" do
      dep = klass.new("foo", [:build])
      dep2 = klass.new("foo", ["bar"])
      dep3 = klass.new("xyz", ["abc"])
      merged = klass.merge_repeats([dep, dep2, dep3])
      expect(merged.count).to eq(2)
      expect(merged.first).to be_a klass

      foo_named_dep = merged.find { |d| d.name == "foo" }
      expect(foo_named_dep.tags).to eq(["bar"])

      xyz_named_dep = merged.find { |d| d.name == "xyz" }
      expect(xyz_named_dep.tags).to eq(["abc"])
    end

    it "merges necessity tags" do
      required_dep = klass.new("foo")
      recommended_dep = klass.new("foo", [:recommended])
      optional_dep = klass.new("foo", [:optional])

      deps = klass.merge_repeats([required_dep, recommended_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).to be_required
      expect(deps.first).not_to be_recommended
      expect(deps.first).not_to be_optional

      deps = klass.merge_repeats([required_dep, optional_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).to be_required
      expect(deps.first).not_to be_recommended
      expect(deps.first).not_to be_optional

      deps = klass.merge_repeats([recommended_dep, optional_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).not_to be_required
      expect(deps.first).to be_recommended
      expect(deps.first).not_to be_optional
    end

    it "merges temporality tags" do
      normal_dep = klass.new("foo")
      build_dep = klass.new("foo", [:build])

      deps = klass.merge_repeats([normal_dep, build_dep])
      expect(deps.count).to eq(1)
      expect(deps.first).not_to be_a_build_dependency
    end
  end

  specify "equality" do
    foo1 = klass.new("foo")
    foo2 = klass.new("foo")
    expect(foo1).to eq(foo2)
    expect(foo1).to eql(foo2)

    bar = klass.new("bar")
    expect(foo1).not_to eq(bar)
    expect(foo1).not_to eql(bar)

    foo3 = klass.new("foo", [:build])
    expect(foo1).not_to eq(foo3)
    expect(foo1).not_to eql(foo3)
  end

  describe "#tap" do
    it "returns a tap passed a fully-qualified name" do
      dependency = klass.new("foo/bar/dog")
      expect(dependency.tap).to eq(Tap.fetch("foo", "bar"))
    end

    it "returns no tap passed a simple name" do
      dependency = klass.new("dog")
      expect(dependency.tap).to be_nil
    end
  end

  specify "#option_names" do
    dependency = klass.new("foo/bar/dog")
    expect(dependency.option_names).to eq(%w[dog])
  end

  describe "with no_linkage tag" do
    it "marks dependency as no_linkage" do
      dep = klass.new("foo", [:no_linkage])
      expect(dep).to be_no_linkage
      expect(dep).to be_required
      expect(dep).not_to be_build
      expect(dep).not_to be_test
    end
  end

  describe "Dependency#installed? with bottle_os_version" do
    subject(:dependency) { klass.new("foo") }

    it "accepts macOS bottle_os_version parameter" do
      expect { dependency.installed?(bottle_os_version: "macOS 14") }.not_to raise_error
    end

    it "accepts Ubuntu bottle_os_version parameter" do
      expect { dependency.installed?(bottle_os_version: "Ubuntu 22.04") }.not_to raise_error
    end
  end

  describe "Dependency#satisfied? with bottle_os_version" do
    subject(:dependency) { klass.new("foo") }

    it "accepts bottle_os_version parameter" do
      expect { dependency.satisfied?(bottle_os_version: "macOS 14") }.not_to raise_error
    end

    it "accepts Ubuntu bottle_os_version parameter" do
      expect { dependency.installed?(bottle_os_version: "Ubuntu 22.04") }.not_to raise_error
    end
  end

  describe "UsesFromMacOSDependency#installed? with bottle_os_version" do
    subject(:uses_from_macos) { klass.new("foo", bounds: { since: :sonoma }) }

    it "accepts macOS bottle_os_version parameter" do
      expect { uses_from_macos.installed?(bottle_os_version: "macOS 14") }.not_to raise_error
    end

    it "accepts Ubuntu bottle_os_version parameter" do
      expect { uses_from_macos.installed?(bottle_os_version: "Ubuntu 22.04") }.not_to raise_error
    end
  end
end
