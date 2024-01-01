# frozen_string_literal: true

require "dependency_collector"

describe DependencyCollector do
  alias_matcher :need_tar_xz_dependency, :be_tar_needs_xz_dependency

  subject(:collector) { described_class.new }

  specify "Resource dependency from a '.xz' URL" do
    resource = Resource.new
    resource.url("https://brew.sh/foo.tar.xz")
    expect(collector.add(resource)).to be_nil
  end

  specify "Resource dependency from a '.zip' URL" do
    resource = Resource.new
    resource.url("https://brew.sh/foo.zip")
    expect(collector.add(resource)).to be_nil
  end

  specify "Resource dependency from a '.bz2' URL" do
    resource = Resource.new
    resource.url("https://brew.sh/foo.tar.bz2")
    expect(collector.add(resource)).to be_nil
  end

  specify "Resource dependency from a '.git' URL" do
    resource = Resource.new
    resource.url("git://brew.sh/foo/bar.git")
    expect(collector.add(resource)).to be_nil
  end

  specify "Resource dependency from a Subversion URL" do
    resource = Resource.new
    resource.url("svn://brew.sh/foo/bar")
    expect(collector.add(resource)).to eq(Dependency.new("subversion", [:build, :test, :implicit]))
  end
end
