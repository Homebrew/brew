# typed: true
# frozen_string_literal: true

require "dependency"

RSpec.describe Dependency do
  let(:klass) { Dependency }
  let(:foo) { build_dep(:foo) }
  let(:bar) { build_dep(:bar) }
  let(:baz) { build_dep(:baz) }
  let(:qux) { build_dep(:qux) }
  let(:deps) { [foo, bar, baz, qux] }
  let(:formula) { instance_double(Formula, deps:, name: "f") }

  def build_dep(name, tags = [], deps = [])
    dep = klass.new(name.to_s, tags)
    allow(dep).to receive(:to_formula).and_return \
      instance_double(Formula, deps:, name:, full_name: name)
    dep
  end

  describe "::expand" do
    it "yields dependent and dependency pairs" do
      i = 0
      klass.expand(formula) do |dependent, dep|
        expect(dependent).to eq(formula)
        expect(deps[i]).to eq(dep)
        i += 1
      end
    end

    it "returns the dependencies" do
      expect(klass.expand(formula)).to eq(deps)
    end

    it "prunes all when given a block with PRUNE" do
      expect(klass.expand(formula) { next Dependable::PRUNE }).to be_empty
    end

    it "can prune selectively" do
      deps = klass.expand(formula) do |_, dep|
        next Dependable::PRUNE if dep.name == "foo"
      end

      expect(deps).to eq([bar, baz, qux])
    end

    it "preserves dependency order" do
      allow(foo).to receive(:to_formula).and_return \
        instance_double(Formula, name: "foo", full_name: "foo", deps: [qux, baz])
      expect(klass.expand(formula)).to eq([qux, baz, foo, bar])
    end
  end

  it "skips optionals by default" do
    deps = [build_dep(:foo, [:optional]), bar, baz, qux]
    f = instance_double(Formula, deps:, build: instance_double(BuildOptions, with?: false), name: "f")
    expect(klass.expand(f)).to eq([bar, baz, qux])
  end

  it "keeps recommended dependencies by default" do
    deps = [build_dep(:foo, [:recommended]), bar, baz, qux]
    f = instance_double(Formula, deps:, build: instance_double(BuildOptions, with?: true), name: "f")
    expect(klass.expand(f)).to eq(deps)
  end

  it "merges repeated dependencies with differing options" do
    foo2 = build_dep(:foo, ["option"])
    baz2 = build_dep(:baz, ["option"])
    deps << foo2 << baz2
    deps = [foo2, bar, baz2, qux]
    deps.zip(klass.expand(formula)) do |expected, actual|
      expect(expected.tags).to eq(actual.tags)
      expect(expected).to eq(actual)
    end
  end

  it "merges tags without duplicating them" do
    foo2 = build_dep(:foo, ["option"])
    foo3 = build_dep(:foo, ["option"])
    deps << foo2 << foo3

    expect(klass.expand(formula).first.tags).to eq(%w[option])
  end

  it "skips parent but yields children with SKIP" do
    f = instance_double(
      Formula,
      name: "f",
      deps: [
        build_dep(:foo, [], [bar, baz]),
        build_dep(:foo, [], [baz]),
      ],
    )

    deps = klass.expand(f) do |_dependent, dep|
      next Dependable::SKIP if %w[foo qux].include? dep.name
    end

    expect(deps).to eq([bar, baz])
  end

  it "keeps dependency but prunes recursive dependencies with KEEP_BUT_PRUNE_RECURSIVE_DEPS" do
    foo = build_dep(:foo, [:test], bar)
    baz = build_dep(:baz, [:test])
    f = instance_double(Formula, name: "f", deps: [foo, baz])

    deps = klass.expand(f) do |_dependent, dep|
      next Dependable::KEEP_BUT_PRUNE_RECURSIVE_DEPS if dep.test?
    end

    expect(deps).to eq([foo, baz])
  end

  it "returns only the dependencies given as a collection as second argument" do
    expect(formula.deps).to eq([foo, bar, baz, qux])
    expect(klass.expand(formula, [bar, baz])).to eq([bar, baz])
  end

  it "doesn't raise an error when a dependency is cyclic" do
    foo = build_dep(:foo)
    bar = build_dep(:bar, [], [foo])
    allow(foo).to receive(:to_formula).and_return \
      instance_double(Formula, deps: [bar], name: foo.name, full_name: foo.name)
    f = instance_double(Formula, name: "f", full_name: "f", deps: [foo, bar])
    expect { klass.expand(f) }.not_to raise_error
  end

  it "cleans the expand stack" do
    foo = build_dep(:foo)
    allow(foo).to receive(:to_formula).and_raise(FormulaUnavailableError, foo.name)
    f = instance_double(Formula, name: "f", deps: [foo])
    expect { klass.expand(f) }.to raise_error(FormulaUnavailableError)
    expect(klass.instance_variable_get(:@expand_stack)).to be_empty
  end
end
