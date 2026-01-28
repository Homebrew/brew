# frozen_string_literal: true

require "ostruct"
require "bundle"
require "bundle/formula_dumper"
require "tsort"
require "formula"
require "tab"
require "utils/bottles"

# TODO: remove OpenStruct usage
# rubocop:todo Style/OpenStructUse
RSpec.describe Homebrew::Bundle::FormulaDumper do
  subject(:dumper) { described_class }

  let(:foo) do
    instance_double(Formula,
                    name:                   "foo",
                    desc:                   "foobar",
                    oldnames:               ["oldfoo"],
                    full_name:              "qux/quuz/foo",
                    any_version_installed?: true,
                    aliases:                ["foobar"],
                    runtime_dependencies:   [],
                    deps:                   [],
                    conflicts:              [],
                    any_installed_prefix:   nil,
                    linked?:                false,
                    keg_only?:              true,
                    pinned?:                false,
                    outdated?:              false,
                    stable:                 OpenStruct.new(bottle_defined?: false, bottled?: false),
                    tap:                    OpenStruct.new(official?: false))
  end
  let(:foo_hash) do
    {
      aliases:                  ["foobar"],
      any_version_installed?:   true,
      args:                     [],
      bottle:                   false,
      bottled:                  false,
      build_dependencies:       [],
      conflicts_with:           [],
      dependencies:             [],
      desc:                     "foobar",
      full_name:                "qux/quuz/foo",
      installed_as_dependency?: false,
      installed_on_request?:    false,
      link?:                    nil,
      name:                     "foo",
      oldnames:                 ["oldfoo"],
      outdated?:                false,
      pinned?:                  false,
      poured_from_bottle?:      false,
      version:                  nil,
      official_tap:             false,
    }
  end
  let(:bar) do
    linked_keg = Pathname("/usr/local").join("var").join("homebrew").join("linked").join("bar")
    instance_double(Formula,
                    name:                   "bar",
                    desc:                   "barfoo",
                    oldnames:               [],
                    full_name:              "bar",
                    any_version_installed?: true,
                    aliases:                [],
                    runtime_dependencies:   [],
                    deps:                   [],
                    conflicts:              [],
                    any_installed_prefix:   nil,
                    linked?:                true,
                    keg_only?:              false,
                    pinned?:                true,
                    outdated?:              true,
                    linked_keg:,
                    stable:                 OpenStruct.new(bottle_defined?: true, bottled?: true),
                    tap:                    OpenStruct.new(official?: true),
                    bottle_hash:            {
                      cellar: ":any",
                      files:  {
                        big_sur: {
                          sha256: "abcdef",
                          url:    "https://brew.sh//foo-1.0.big_sur.bottle.tar.gz",
                        },
                      },
                    })
  end
  let(:bar_hash) do
    {
      aliases:                  [],
      any_version_installed?:   true,
      args:                     [],
      bottle:                   {
        cellar: ":any",
        files:  {
          big_sur: {
            sha256: "abcdef",
            url:    "https://brew.sh//foo-1.0.big_sur.bottle.tar.gz",
          },
        },
      },
      bottled:                  true,
      build_dependencies:       [],
      conflicts_with:           [],
      dependencies:             [],
      desc:                     "barfoo",
      full_name:                "bar",
      installed_as_dependency?: false,
      installed_on_request?:    false,
      link?:                    nil,
      name:                     "bar",
      oldnames:                 [],
      outdated?:                true,
      pinned?:                  true,
      poured_from_bottle?:      true,
      version:                  "1.0",
      official_tap:             true,
    }
  end
  let(:baz) do
    instance_double(Formula,
                    name:                   "baz",
                    desc:                   "",
                    oldnames:               [],
                    full_name:              "bazzles/bizzles/baz",
                    any_version_installed?: true,
                    aliases:                [],
                    runtime_dependencies:   [OpenStruct.new(name: "bar")],
                    deps:                   [OpenStruct.new(name: "bar", build?: true)],
                    conflicts:              [],
                    any_installed_prefix:   nil,
                    linked?:                false,
                    keg_only?:              false,
                    pinned?:                false,
                    outdated?:              false,
                    stable:                 OpenStruct.new(bottle_defined?: false, bottled?: false),
                    tap:                    OpenStruct.new(official?: false))
  end
  let(:baz_hash) do
    {
      aliases:                  [],
      any_version_installed?:   true,
      args:                     [],
      bottle:                   false,
      bottled:                  false,
      build_dependencies:       ["bar"],
      conflicts_with:           [],
      dependencies:             ["bar"],
      desc:                     "",
      full_name:                "bazzles/bizzles/baz",
      installed_as_dependency?: false,
      installed_on_request?:    false,
      link?:                    false,
      name:                     "baz",
      oldnames:                 [],
      outdated?:                false,
      pinned?:                  false,
      poured_from_bottle?:      false,
      version:                  nil,
      official_tap:             false,
    }
  end

  before do
    described_class.reset!
  end

  describe "#formulae" do
    it "returns an empty array when no formulae are installed" do
      expect(dumper.formulae).to be_empty
    end
  end

  describe "#formulae_by_full_name" do
    it "returns an empty hash when no formulae are installed" do
      expect(dumper.formulae_by_full_name).to eql({})
    end

    it "returns an empty hash for an unavailable formula" do
      expect(Formula).to receive(:[]).with("bar").and_raise(FormulaUnavailableError.new("bar"))
      expect(dumper.formulae_by_full_name("bar")).to eql({})
    end

    it "exits on cyclic exceptions" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expect_any_instance_of(Homebrew::Bundle::FormulaDumper::Topo).to receive(:tsort).and_raise(
        TSort::Cyclic,
        'topological sort failed: ["foo", "bar"]',
      )
      expect { dumper.formulae_by_full_name }.to raise_error(SystemExit)
    end

    it "returns a hash for a formula" do
      expect(Formula).to receive(:[]).with("qux/quuz/foo").and_return(foo)
      expect(dumper.formulae_by_full_name("qux/quuz/foo")).to eql(foo_hash)
    end

    it "returns an array for all formulae" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expect(bar.linked_keg).to receive(:realpath).and_return(OpenStruct.new(basename: "1.0"))
      expect(Tab).to receive(:for_keg).with(bar.linked_keg).and_return(
        instance_double(Tab,
                        installed_as_dependency: false,
                        installed_on_request:    false,
                        poured_from_bottle:      true,
                        runtime_dependencies:    [],
                        used_options:            []),
      )
      expect(dumper.formulae_by_full_name).to eql({
        "bar"                 => bar_hash,
        "qux/quuz/foo"        => foo_hash,
        "bazzles/bizzles/baz" => baz_hash,
      })
    end
  end

  describe "#formulae_by_name" do
    it "returns a hash for a formula" do
      expect(Formula).to receive(:[]).with("foo").and_return(foo)
      expect(dumper.formulae_by_name("foo")).to eql(foo_hash)
    end
  end

  describe "#dump" do
    it "returns a dump string with installed formulae" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      allow(Utils).to receive(:safe_popen_read).and_return("")
      expected = <<~EOS
        # barfoo
        brew "bar"
        brew "bazzles/bizzles/baz", link: false
        # foobar
        brew "qux/quuz/foo"
      EOS
      expect(dumper.dump(describe: true)).to eql(expected.chomp)
    end
  end

  describe "#formula_aliases" do
    it "returns an empty string when no formulae are installed" do
      expect(dumper.formula_aliases).to eql({})
    end

    it "returns a hash with installed formulae aliases" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expect(dumper.formula_aliases).to eql({
        "qux/quuz/foobar" => "qux/quuz/foo",
        "foobar"          => "qux/quuz/foo",
      })
    end
  end

  describe "#formula_oldnames" do
    it "returns an empty string when no formulae are installed" do
      expect(dumper.formula_oldnames).to eql({})
    end

    it "returns a hash with installed formulae old names" do
      expect(Formula).to receive(:installed).and_return([foo, bar, baz])
      expect(dumper.formula_oldnames).to eql({
        "qux/quuz/oldfoo" => "qux/quuz/foo",
        "oldfoo"          => "qux/quuz/foo",
      })
    end
  end
end
# rubocop:enable Style/OpenStructUse
