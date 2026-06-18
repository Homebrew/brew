# typed: true
# frozen_string_literal: true

require "dependency_collector"
require "sandbox"

RSpec.describe DependencyCollector do
  subject(:collector) { described_class.new }

  alias_matcher :be_a_build_requirement, :be_build

  describe "#add" do
    let(:resource) { Resource.new }

    context "when xz, unzip and bzip2 are not available" do
      it "creates a resource dependency from a '.xz' URL" do
        resource.url("https://brew.sh/foo.xz")
        allow_any_instance_of(Object).to receive(:which).with("xz")
        expect(collector.add(resource)).to eq(Dependency.new("xz", [:build, :test, :implicit]))
      end

      it "creates a resource dependency from a '.zip' URL" do
        resource.url("https://brew.sh/foo.zip")
        allow_any_instance_of(Object).to receive(:which).with("unzip")
        expect(collector.add(resource)).to eq(Dependency.new("unzip", [:build, :test, :implicit]))
      end

      it "creates a resource dependency from a '.bz2' URL" do
        resource.url("https://brew.sh/foo.tar.bz2")
        allow_any_instance_of(Object).to receive(:which).with("bzip2")
        expect(collector.add(resource)).to eq(Dependency.new("bzip2", [:build, :test, :implicit]))
      end
    end

    context "when xz, zip and bzip2 are available" do
      it "does not create a resource dependency from a '.xz' URL" do
        resource.url("https://brew.sh/foo.xz")
        allow_any_instance_of(Object).to receive(:which).with("xz").and_return(Pathname.new("foo"))
        expect(collector.add(resource)).to be_nil
      end

      it "does not create a resource dependency from a '.zip' URL" do
        resource.url("https://brew.sh/foo.zip")
        allow_any_instance_of(Object).to receive(:which).with("unzip").and_return(Pathname.new("foo"))
        expect(collector.add(resource)).to be_nil
      end

      it "does not create a resource dependency from a '.bz2' URL" do
        resource.url("https://brew.sh/foo.tar.bz2")
        allow_any_instance_of(Object).to receive(:which).with("bzip2").and_return(Pathname.new("foo"))
        expect(collector.add(resource)).to be_nil
      end
    end
  end

  describe "#bubblewrap_dep_if_needed" do
    let(:formulae) do
      Hash.new { |hash, name| hash[name] = instance_double(Formula, deps: []) }
    end

    around do |example|
      with_env(HOMEBREW_TESTS: nil) { example.run }
    end

    before do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(true)
      allow(DevelopmentTools).to receive(:needs_build_formulae?).and_return(false)
      allow(Sandbox).to receive(:executable)
      allow(OS).to receive(:not_tier_one_configuration?).and_return(false)
      allow(Formula).to receive(:[]) { |name| formulae[name] }
      global_dep_tree.clear
    end

    after do
      global_dep_tree.clear
    end

    def global_dep_tree
      OS::Linux::DependencyCollector.module_eval { class_variable_get(:@@global_dep_tree) }
    end

    it "returns a Bubblewrap implicit dependency when the Linux sandbox needs one" do
      expect(collector.bubblewrap_dep_if_needed(Set.new)).to eq(Dependency.new("bubblewrap", [:implicit]))
    end

    it "returns nil when Bubblewrap is already available" do
      allow(Sandbox).to receive(:executable).and_return(Pathname("/usr/bin/bwrap"))

      expect(collector.bubblewrap_dep_if_needed(Set.new)).to be_nil
    end

    it "returns nil for Bubblewrap and its dependencies" do
      collector.send(:global_dep_tree)["bubblewrap"] = Set["libcap"]

      expect(collector.bubblewrap_dep_if_needed(Set["bubblewrap"])).to be_nil
      expect(collector.bubblewrap_dep_if_needed(Set["libcap"])).to be_nil
    end

    it "returns nil when Bubblewrap is already in the dependency tree" do
      expect(collector.bubblewrap_dep_if_needed(Set["bubblewrap"])).to be_nil
    end

    it "returns nil when a Bubblewrap runtime dependency is already in the dependency tree" do
      formulae["bubblewrap"] = instance_double(Formula, deps: [Dependency.new("libcap")])

      expect(collector.bubblewrap_dep_if_needed(Set["libcap"])).to be_nil
    end

    it "ignores Bubblewrap build dependencies when build formulae are not needed" do
      formulae["bubblewrap"] = instance_double(Formula, deps: [
        Dependency.new("libcap"),
        Dependency.new("pkgconf", [:build]),
      ])

      expect(collector.bubblewrap_dep_if_needed(Set["pkgconf"])).to eq(Dependency.new("bubblewrap", [:implicit]))
    end

    it "includes Bubblewrap build dependencies when build formulae are needed" do
      allow(DevelopmentTools).to receive(:needs_build_formulae?).and_return(true)
      formulae["bubblewrap"] = instance_double(Formula, deps: [
        Dependency.new("pkgconf", [:build]),
      ])
      formulae["glibc"]
      formulae[OS::LINUX_PREFERRED_GCC_RUNTIME_FORMULA]

      expect(collector.bubblewrap_dep_if_needed(Set["pkgconf"])).to be_nil
    end
  end
end
