# frozen_string_literal: true

require "dependency_collector"

describe DependencyCollector do
  alias_matcher :be_a_build_requirement, :be_build

  subject(:collector) { described_class.new }

  def find_dependency(name)
    collector.deps.find { |dep| dep.name == name }
  end

  def find_requirement(klass)
    collector.requirements.find { |req| req.is_a? klass }
  end

  describe "#add" do
    specify "dependency creation" do
      collector.add "foo" => :build
      collector.add "bar" => ["--universal", :optional]
      expect(find_dependency("foo")).to be_an_instance_of(Dependency)
      expect(find_dependency("bar").tags.count).to eq(2)
    end

    it "returns the created dependency" do
      expect(collector.add("foo")).to eq(Dependency.new("foo"))
    end

    specify "requirement creation" do
      collector.add :xcode
      expect(find_requirement(XcodeRequirement)).to be_an_instance_of(XcodeRequirement)
    end

    it "deduplicates requirements" do
      2.times { collector.add :xcode }
      expect(collector.requirements.count).to eq(1)
    end

    specify "requirement tags" do
      collector.add xcode: :build
      expect(find_requirement(XcodeRequirement)).to be_a_build_requirement
    end

    it "doesn't mutate the dependency spec" do
      spec = { "foo" => :optional }
      copy = spec.dup
      collector.add(spec)
      expect(spec).to eq(copy)
    end

    it "creates a resource dependency from a CVS URL" do
      resource = Resource.new
      resource.url(":pserver:anonymous:@brew.sh:/cvsroot/foo/bar", using: :cvs)
      expect(collector.add(resource)).to eq(Dependency.new("cvs", [:build, :test, :implicit]))
    end

    it "creates a resource dependency from a '.7z' URL" do
      resource = Resource.new
      resource.url("https://brew.sh/foo.7z")
      expect(collector.add(resource)).to eq(Dependency.new("p7zip", [:build, :test, :implicit]))
    end

    it "creates a resource dependency from a '.gz' URL" do
      resource = Resource.new
      resource.url("https://brew.sh/foo.tar.gz")
      expect(collector.add(resource)).to be_nil
    end

    it "creates a resource dependency from a '.lz' URL" do
      resource = Resource.new
      resource.url("https://brew.sh/foo.lz")
      expect(collector.add(resource)).to eq(Dependency.new("lzip", [:build, :test, :implicit]))
    end

    it "creates a resource dependency from a '.lha' URL" do
      resource = Resource.new
      resource.url("https://brew.sh/foo.lha")
      expect(collector.add(resource)).to eq(Dependency.new("lha", [:build, :test, :implicit]))
    end

    it "creates a resource dependency from a '.lzh' URL" do
      resource = Resource.new
      resource.url("https://brew.sh/foo.lzh")
      expect(collector.add(resource)).to eq(Dependency.new("lha", [:build, :test, :implicit]))
    end

    it "creates a resource dependency from a '.rar' URL" do
      resource = Resource.new
      resource.url("https://brew.sh/foo.rar")
      expect(collector.add(resource)).to eq(Dependency.new("libarchive", [:build, :test, :implicit]))
    end

    it "raises a TypeError for unknown classes" do
      expect { collector.add(Class.new) }.to raise_error(TypeError)
    end

    it "raises a TypeError for unknown Types" do
      expect { collector.add(Object.new) }.to raise_error(TypeError)
    end

    it "raises a TypeError for a Resource with an unknown download strategy" do
      resource = Resource.new
      resource.download_strategy = Class.new
      expect { collector.add(resource) }.to raise_error(TypeError)
    end
  end
end
