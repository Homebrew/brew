# frozen_string_literal: true

require "tab"
require "formula"

RSpec.describe Tab do
  alias_matcher :be_built_with, :be_with

  matcher :be_poured_from_bottle do
    match do |actual|
      actual.poured_from_bottle == true
    end
  end

  matcher :be_built_as_bottle do
    match do |actual|
      actual.built_as_bottle == true
    end
  end

  subject(:tab) do
    described_class.new(
      "homebrew_version"     => HOMEBREW_VERSION,
      "used_options"         => used_options.as_flags,
      "unused_options"       => unused_options.as_flags,
      "built_as_bottle"      => false,
      "poured_from_bottle"   => true,
      "changed_files"        => [],
      "time"                 => time,
      "source_modified_time" => 0,
      "compiler"             => "clang",
      "stdlib"               => "libcxx",
      "runtime_dependencies" => [],
      "source"               => {
        "tap"      => CoreTap.instance.to_s,
        "path"     => CoreTap.instance.path.to_s,
        "spec"     => "stable",
        "versions" => {
          "stable" => "0.10",
          "head"   => "HEAD-1111111",
        },
      },
      "arch"                 => Hardware::CPU.arch,
      "built_on"             => DevelopmentTools.build_system_info,
    )
  end

  let(:time) { Time.now.to_i }
  let(:unused_options) { Options.create(%w[--with-baz --without-qux]) }
  let(:used_options) { Options.create(%w[--with-foo --without-bar]) }

  let(:f) { formula { url "foo-1.0" } }
  let(:f_tab_path) { f.prefix/"INSTALL_RECEIPT.json" }
  let(:f_tab_content) { (TEST_FIXTURE_DIR/"receipt.json").read }

  specify "defaults" do
    # < 1.1.7 runtime_dependencies were wrong so are ignored
    stub_const("HOMEBREW_VERSION", "1.1.7")

    tab = described_class.empty

    expect(tab.homebrew_version).to eq(HOMEBREW_VERSION)
    expect(tab.unused_options).to be_empty
    expect(tab.used_options).to be_empty
    expect(tab.changed_files).to be_nil
    expect(tab).not_to be_built_as_bottle
    expect(tab).not_to be_poured_from_bottle
    expect(tab).to be_stable
    expect(tab).not_to be_head
    expect(tab.tap).to be_nil
    expect(tab.time).to be_nil
    expect(tab.runtime_dependencies).to be_nil
    expect(tab.stable_version).to be_nil
    expect(tab.head_version).to be_nil
    expect(tab.cxxstdlib.compiler).to eq(DevelopmentTools.default_compiler)
    expect(tab.cxxstdlib.type).to be_nil
    expect(tab.source["path"]).to be_nil
  end

  specify "#include?" do
    expect(tab).to include("with-foo")
    expect(tab).to include("without-bar")
  end

  specify "#with?" do
    expect(tab).to be_built_with("foo")
    expect(tab).to be_built_with("qux")
    expect(tab).not_to be_built_with("bar")
    expect(tab).not_to be_built_with("baz")
  end

  specify "#parsed_homebrew_version" do
    tab = described_class.new
    expect(tab.parsed_homebrew_version).to be Version::NULL

    tab = described_class.new(homebrew_version: "1.2.3")
    expect(tab.parsed_homebrew_version).to eq("1.2.3")
    expect(tab.parsed_homebrew_version).to be < "1.2.3-1-g12789abdf"
    expect(tab.parsed_homebrew_version).to be_a(Version)

    tab.homebrew_version = "1.2.4-567-g12789abdf"
    expect(tab.parsed_homebrew_version).to be > "1.2.4"
    expect(tab.parsed_homebrew_version).to be > "1.2.4-566-g21789abdf"
    expect(tab.parsed_homebrew_version).to be < "1.2.4-568-g01789abdf"

    tab = described_class.new(homebrew_version: "2.0.0-134-gabcdefabc-dirty")
    expect(tab.parsed_homebrew_version).to be > "2.0.0"
    expect(tab.parsed_homebrew_version).to be > "2.0.0-133-g21789abdf"
    expect(tab.parsed_homebrew_version).to be < "2.0.0-135-g01789abdf"
  end

  specify "#runtime_dependencies" do
    tab = described_class.new
    expect(tab.runtime_dependencies).to be_nil

    tab.homebrew_version = "1.1.6"
    expect(tab.runtime_dependencies).to be_nil

    tab.runtime_dependencies = []
    expect(tab.runtime_dependencies).not_to be_nil

    tab.homebrew_version = "1.1.5"
    expect(tab.runtime_dependencies).to be_nil

    tab.homebrew_version = "1.1.7"
    expect(tab.runtime_dependencies).not_to be_nil

    tab.homebrew_version = "1.1.10"
    expect(tab.runtime_dependencies).not_to be_nil

    tab.runtime_dependencies = [{ "full_name" => "foo", "version" => "1.0" }]
    expect(tab.runtime_dependencies).not_to be_nil
  end

  specify "::runtime_deps_hash" do
    runtime_deps = [Dependency.new("foo")]
    foo = formula("foo") { url "foo-1.0" }
    stub_formula_loader foo
    runtime_deps_hash = described_class.runtime_deps_hash(foo, runtime_deps)
    tab = described_class.new
    tab.homebrew_version = "1.1.6"
    tab.runtime_dependencies = runtime_deps_hash
    expect(tab.runtime_dependencies).to eql(
      [{ "full_name" => "foo", "version" => "1.0", "revision" => 0, "pkg_version" => "1.0",
"declared_directly" => false }],
    )
  end

  specify "#cxxstdlib" do
    expect(tab.cxxstdlib.compiler).to eq(:clang)
    expect(tab.cxxstdlib.type).to eq(:libcxx)
  end

  specify "other attributes" do
    expect(tab.tap.name).to eq("homebrew/core")
    expect(tab.time).to eq(time)
    expect(tab).not_to be_built_as_bottle
    expect(tab).to be_poured_from_bottle
  end

  describe "::from_file" do
    it "parses a Tab from a file" do
      path = Pathname.new("#{TEST_FIXTURE_DIR}/receipt.json")
      tab = described_class.from_file(path)
      source_path = "/usr/local/Library/Taps/homebrew/homebrew-core/Formula/foo.rb"
      runtime_dependencies = [{ "full_name" => "foo", "version" => "1.0" }]
      changed_files = %w[INSTALL_RECEIPT.json bin/foo]

      expect(tab.used_options.sort).to eq(used_options.sort)
      expect(tab.unused_options.sort).to eq(unused_options.sort)
      expect(tab.changed_files).to eq(changed_files)
      expect(tab).not_to be_built_as_bottle
      expect(tab).to be_poured_from_bottle
      expect(tab).to be_stable
      expect(tab).not_to be_head
      expect(tab.tap.name).to eq("homebrew/core")
      expect(tab.spec).to eq(:stable)
      expect(tab.time).to eq(Time.at(1_403_827_774).to_i)
      expect(tab.cxxstdlib.compiler).to eq(:clang)
      expect(tab.cxxstdlib.type).to eq(:libcxx)
      expect(tab.runtime_dependencies).to eq(runtime_dependencies)
      expect(tab.stable_version.to_s).to eq("2.14")
      expect(tab.head_version.to_s).to eq("HEAD-0000000")
      expect(tab.source["path"]).to eq(source_path)
    end
  end

  describe "::from_file_content" do
    it "parses a Tab from a file" do
      path = Pathname.new("#{TEST_FIXTURE_DIR}/receipt.json")
      tab = described_class.from_file_content(path.read, path)
      source_path = "/usr/local/Library/Taps/homebrew/homebrew-core/Formula/foo.rb"
      runtime_dependencies = [{ "full_name" => "foo", "version" => "1.0" }]
      changed_files = %w[INSTALL_RECEIPT.json bin/foo]

      expect(tab.used_options.sort).to eq(used_options.sort)
      expect(tab.unused_options.sort).to eq(unused_options.sort)
      expect(tab.changed_files).to eq(changed_files)
      expect(tab).not_to be_built_as_bottle
      expect(tab).to be_poured_from_bottle
      expect(tab).to be_stable
      expect(tab).not_to be_head
      expect(tab.tap.name).to eq("homebrew/core")
      expect(tab.spec).to eq(:stable)
      expect(tab.time).to eq(Time.at(1_403_827_774).to_i)
      expect(tab.cxxstdlib.compiler).to eq(:clang)
      expect(tab.cxxstdlib.type).to eq(:libcxx)
      expect(tab.runtime_dependencies).to eq(runtime_dependencies)
      expect(tab.stable_version.to_s).to eq("2.14")
      expect(tab.head_version.to_s).to eq("HEAD-0000000")
      expect(tab.source["path"]).to eq(source_path)
    end

    it "can parse an old Tab file" do
      path = Pathname.new("#{TEST_FIXTURE_DIR}/receipt_old.json")
      tab = described_class.from_file_content(path.read, path)

      expect(tab.used_options.sort).to eq(used_options.sort)
      expect(tab.unused_options.sort).to eq(unused_options.sort)
      expect(tab).not_to be_built_as_bottle
      expect(tab).to be_poured_from_bottle
      expect(tab).to be_stable
      expect(tab).not_to be_head
      expect(tab.tap.name).to eq("homebrew/core")
      expect(tab.spec).to eq(:stable)
      expect(tab.time).to eq(Time.at(1_403_827_774).to_i)
      expect(tab.cxxstdlib.compiler).to eq(:clang)
      expect(tab.cxxstdlib.type).to eq(:libcxx)
      expect(tab.runtime_dependencies).to be_nil
    end

    it "raises a parse exception message including the Tab filename" do
      expect { described_class.from_file_content("''", "receipt.json") }.to raise_error(
        JSON::ParserError,
        /receipt.json:/,
      )
    end
  end

  describe "::create" do
    it "creates a Tab" do
      # < 1.1.7 runtime dependencies were wrong so are ignored
      stub_const("HOMEBREW_VERSION", "1.1.7")

      # don't try to load gcc/glibc
      allow(DevelopmentTools).to receive_messages(needs_libc_formula?: false, needs_compiler_formula?: false)

      f = formula do
        url "foo-1.0"
        depends_on "bar"
        depends_on "user/repo/from_tap"
        depends_on "baz" => :build
      end

      tap = Tap.fetch("user", "repo")
      from_tap = formula("from_tap", path: tap.path/"Formula/from_tap.rb") do
        url "from_tap-1.0"
        revision 1
      end
      stub_formula_loader from_tap

      stub_formula_loader formula("bar") { url "bar-2.0" }
      stub_formula_loader formula("baz") { url "baz-3.0" }

      compiler = DevelopmentTools.default_compiler
      stdlib = :libcxx
      tab = described_class.create(f, compiler, stdlib)

      runtime_dependencies = [
        { "full_name" => "bar", "version" => "2.0", "revision" => 0, "pkg_version" => "2.0",
"declared_directly" => true },
        { "full_name" => "user/repo/from_tap", "version" => "1.0", "revision" => 1, "pkg_version" => "1.0_1",
"declared_directly" => true },
      ]
      expect(tab.runtime_dependencies).to eq(runtime_dependencies)

      expect(tab.source["path"]).to eq(f.path.to_s)
    end

    it "can create a Tab from an alias" do
      alias_path = CoreTap.instance.alias_dir/"bar"
      f = formula(alias_path:) { url "foo-1.0" }
      compiler = DevelopmentTools.default_compiler
      stdlib = :libcxx
      tab = described_class.create(f, compiler, stdlib)

      expect(tab.source["path"]).to eq(f.alias_path.to_s)
    end
  end

  describe "::for_keg" do
    subject(:tab_for_keg) { described_class.for_keg(f.prefix) }

    it "creates a Tab for a given Keg" do
      f.prefix.mkpath
      f_tab_path.write f_tab_content

      expect(tab_for_keg.tabfile).to eq(f_tab_path)
    end

    it "can create a Tab for a non-existent Keg" do
      f.prefix.mkpath

      expect(tab_for_keg.tabfile).to eq(f_tab_path)
    end
  end

  describe "::for_formula" do
    it "creates a Tab for a given Formula" do
      tab = described_class.for_formula(f)
      expect(tab.source["path"]).to eq(f.path.to_s)
    end

    it "can create a Tab for for a Formula from an alias" do
      alias_path = CoreTap.instance.alias_dir/"bar"
      f = formula(alias_path:) { url "foo-1.0" }

      tab = described_class.for_formula(f)
      expect(tab.source["path"]).to eq(alias_path.to_s)
    end

    it "creates a Tab for a given Formula with existing Tab" do
      f.prefix.mkpath
      f_tab_path.write f_tab_content

      tab = described_class.for_formula(f)
      expect(tab.tabfile).to eq(f_tab_path)
    end

    it "can create a Tab for a non-existent Formula" do
      f.prefix.mkpath

      tab = described_class.for_formula(f)
      expect(tab.tabfile).to be_nil
    end

    it "can create a Tab for a Formula with multiple Kegs" do
      f.prefix.mkpath
      f_tab_path.write f_tab_content

      f2 = formula { url "foo-2.0" }
      f2.prefix.mkpath

      expect(f2.rack).to eq(f.rack)
      expect(f.installed_prefixes.length).to eq(2)

      tab = described_class.for_formula(f)
      expect(tab.tabfile).to eq(f_tab_path)
    end

    it "can create a Tab for a Formula with an outdated Kegs" do
      f.prefix.mkpath
      f_tab_path.write f_tab_content

      f2 = formula { url "foo-2.0" }

      expect(f2.rack).to eq(f.rack)
      expect(f.installed_prefixes.length).to eq(1)

      tab = described_class.for_formula(f)
      expect(tab.tabfile).to eq(f_tab_path)
    end
  end

  specify "#to_json" do
    json_tab = described_class.new(JSON.parse(tab.to_json))
    expect(json_tab.homebrew_version).to eq(tab.homebrew_version)
    expect(json_tab.used_options.sort).to eq(tab.used_options.sort)
    expect(json_tab.unused_options.sort).to eq(tab.unused_options.sort)
    expect(json_tab.built_as_bottle).to eq(tab.built_as_bottle)
    expect(json_tab.poured_from_bottle).to eq(tab.poured_from_bottle)
    expect(json_tab.changed_files).to eq(tab.changed_files)
    expect(json_tab.tap).to eq(tab.tap)
    expect(json_tab.spec).to eq(tab.spec)
    expect(json_tab.time).to eq(tab.time)
    expect(json_tab.compiler).to eq(tab.compiler)
    expect(json_tab.stdlib).to eq(tab.stdlib)
    expect(json_tab.runtime_dependencies).to eq(tab.runtime_dependencies)
    expect(json_tab.stable_version).to eq(tab.stable_version)
    expect(json_tab.head_version).to eq(tab.head_version)
    expect(json_tab.source["path"]).to eq(tab.source["path"])
    expect(json_tab.arch).to eq(tab.arch.to_s)
    expect(json_tab.built_on["os"]).to eq(tab.built_on["os"])
  end

  specify "#to_bottle_hash" do
    json_tab = described_class.new(JSON.parse(tab.to_bottle_hash.to_json))
    expect(json_tab.homebrew_version).to eq(tab.homebrew_version)
    expect(json_tab.changed_files).to eq(tab.changed_files)
    expect(json_tab.source_modified_time).to eq(tab.source_modified_time)
    expect(json_tab.stdlib).to eq(tab.stdlib)
    expect(json_tab.compiler).to eq(tab.compiler)
    expect(json_tab.runtime_dependencies).to eq(tab.runtime_dependencies)
    expect(json_tab.arch).to eq(tab.arch.to_s)
    expect(json_tab.built_on["os"]).to eq(tab.built_on["os"])
  end

  specify "::remap_deprecated_options" do
    deprecated_options = [DeprecatedOption.new("with-foo", "with-foo-new")]
    remapped_options = described_class.remap_deprecated_options(deprecated_options, tab.used_options)
    expect(remapped_options).to include(Option.new("without-bar"))
    expect(remapped_options).to include(Option.new("with-foo-new"))
  end
end
