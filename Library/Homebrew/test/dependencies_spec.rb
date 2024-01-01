# frozen_string_literal: true

require "dependencies"
require "dependency"

describe Dependencies do
  subject(:dependencies) { described_class.new }

  describe "#<<" do
    it "returns itself" do
      expect(dependencies << Dependency.new("foo")).to eq(dependencies)
    end

    it "preserves order" do
      hash = { 0 => "foo", 1 => "bar", 2 => "baz" }

      dependencies << Dependency.new(hash[0])
      dependencies << Dependency.new(hash[1])
      dependencies << Dependency.new(hash[2])

      dependencies.each_with_index do |dep, i|
        expect(dep.name).to eq(hash[i])
      end
    end
  end

  specify "#*" do
    dependencies << Dependency.new("foo")
    dependencies << Dependency.new("bar")
    expect(dependencies * ", ").to eq("foo, bar")
  end

  specify "#to_a" do
    dep = Dependency.new("foo")
    dependencies << dep
    expect(dependencies.to_a).to eq([dep])
  end

  specify "#to_ary" do
    dep = Dependency.new("foo")
    dependencies << dep
    expect(dependencies.to_ary).to eq([dep])
  end

  specify "type helpers" do
    foo = Dependency.new("foo")
    bar = Dependency.new("bar", [:optional])
    baz = Dependency.new("baz", [:build])
    qux = Dependency.new("qux", [:recommended])
    quux = Dependency.new("quux")
    dependencies << foo << bar << baz << qux << quux
    expect(dependencies.required).to eq([foo, quux])
    expect(dependencies.optional).to eq([bar])
    expect(dependencies.build).to eq([baz])
    expect(dependencies.recommended).to eq([qux])
    expect(dependencies.default.sort_by(&:name)).to eq([foo, baz, quux, qux].sort_by(&:name))
  end

  specify "equality" do
    a = described_class.new
    b = described_class.new

    dep = Dependency.new("foo")

    a << dep
    b << dep

    expect(a).to eq(b)
    expect(a).to eql(b)

    b << Dependency.new("bar", [:optional])

    expect(a).not_to eq(b)
    expect(a).not_to eql(b)
  end

  specify "#empty?" do
    expect(dependencies).to be_empty

    dependencies << Dependency.new("foo")
    expect(dependencies).not_to be_empty
  end

  specify "#inspect" do
    expect(dependencies.inspect).to eq("#<Dependencies: []>")

    dependencies << Dependency.new("foo")
    expect(dependencies.inspect).to eq("#<Dependencies: [#<Dependency: \"foo\" []>]>")
  end
end
