# typed: true
# frozen_string_literal: true

require "dependency_collector"

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

  describe "#implicit_dependency_names" do
    let(:formulae) do
      Hash.new { |hash, name| hash[name] = instance_double(Formula, deps: []) }
    end

    before do
      allow(DevelopmentTools).to receive_messages(needs_build_formulae?: false, needs_libc_formula?: false)
      allow(Formula).to receive(:[]) { |name| formulae[name] }
      global_dep_tree.clear
    end

    after do
      global_dep_tree.clear
    end

    def global_dep_tree
      OS::Linux::DependencyCollector.module_eval { class_variable_get(:@@global_dep_tree) }
    end

    it "is empty when build formulae and a libc formula aren't needed" do
      expect(collector.implicit_dependency_names).to eq(Set.new)
    end

    it "includes gcc when build formulae are needed" do
      allow(DevelopmentTools).to receive(:needs_build_formulae?).and_return(true)

      expect(collector.implicit_dependency_names).to include(OS::LINUX_PREFERRED_GCC_RUNTIME_FORMULA)
    end

    it "includes glibc when a libc formula is needed" do
      allow(DevelopmentTools).to receive(:needs_libc_formula?).and_return(true)

      expect(collector.implicit_dependency_names).to include("glibc")
    end
  end
end
