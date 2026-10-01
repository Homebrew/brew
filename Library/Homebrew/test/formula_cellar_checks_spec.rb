# typed: true
# frozen_string_literal: true

require "formula_cellar_checks"
require "formula"

RSpec.describe FormulaCellarChecks do
  include FileUtils

  subject(:checks) { checker_class.new(f) }

  let(:checker_class) do
    Class.new do
      include FormulaCellarChecks

      attr_reader :formula
      attr_writer :strict

      def initialize(formula)
        @formula = formula
      end

      def problem_if_output(output); end
    end
  end

  let(:tap) { instance_double(Tap, core_tap?: true) }
  let(:f) do
    formula("cellar_checks_test") do
      T.bind(self, T.class_of(Formula))
      url "foo-1.0"
    end
  end

  before do
    f.prefix.mkpath
    allow(f).to receive(:tap).and_return(tap)
    allow(tap).to receive(:audit_exception).with(:prebuilt_binary_allowlist, f.name).and_return(false)
  end

  after { FileUtils.rm_rf(npm_cache) }

  def npm_cache
    Homebrew::PackageManagerCache.path("npm_cache")/"_cacache"
  end

  def executable = TEST_FIXTURE_DIR/(OS.mac? ? "mach/a.out" : "elf/hello")
  def library = TEST_FIXTURE_DIR/(OS.mac? ? "mach/x86_64.dylib" : "elf/libhello.so.0")
  def library_name = OS.mac? ? "libbar.dylib" : "libbar.so.0"

  def install_at(libexec_path, fixture = executable)
    target = f.libexec/libexec_path
    target.dirname.mkpath
    cp fixture, target
    target
  end

  # Writes one package tarball into npm's cache, recorded in its index under
  # each given key, the way npm stores what it fetched or packed.
  def cache_package(members, name: "pkg", keys: nil)
    require "rubygems/package"
    require "zlib"

    keys ||= ["make-fetch-happen:request-cache:https://registry.npmjs.org/#{name}/-/#{name}-1.0.0.tgz"]
    members = { "package/package.json" => %Q({"name":"#{name}","version":"1.0.0"}) }.merge(members)
    buffer = StringIO.new(+"", "wb")
    Zlib::GzipWriter.wrap(buffer) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        members.each do |member, body|
          tar.add_file_simple(member, 0644, body.bytesize) { |io| io.write(body) }
        end
      end
    end
    tarball = buffer.string

    hex = Digest::SHA512.hexdigest(tarball)
    content = npm_cache/"content-v2/sha512"/hex[0, 2]/hex[2, 2]/hex[4..]
    content.dirname.mkpath
    content.binwrite(tarball)

    index = npm_cache/"index-v5/00/00/index"
    index.dirname.mkpath
    integrity = "sha512-#{[[hex].pack("H*")].pack("m0")}"
    index.open("a") do |io|
      keys.each { |key| io.puts("0000\t#{JSON.generate({ key:, integrity: })}") }
    end
  end

  def local_key(name) = "pacote:tarball:file:/tmp/#{name}-1.0.0.tgz"
  def download_key(name) = "make-fetch-happen:request-cache:https://registry.npmjs.org/#{name}/-/#{name}-1.0.0.tgz"

  def append_index_record(record)
    index = npm_cache/"index-v5/00/00/index"
    index.dirname.mkpath
    index.open("a") { |io| io.puts("0000\t#{JSON.generate(record)}") }
  end

  describe "#audit_installed" do
    before { allow(f).to receive(:tap).and_return(nil) }

    it "does not check for prebuilt npm binaries by default" do
      expect(checks).not_to receive(:check_prebuilt_npm_binaries)
      checks.audit_installed
    end

    it "checks for prebuilt npm binaries when strict" do
      checks.strict = true
      expect(checks).to receive(:check_prebuilt_npm_binaries).with(f)
      checks.audit_installed
    end
  end

  describe "#binary_program?", :needs_linux do
    def elf(name) = ELFPathname.wrap(TEST_FIXTURE_DIR/"elf"/name)

    it "is true for a dynamically linked executable" do
      expect(checks.binary_program?(elf("hello"))).to be true
    end

    it "is true for a static position-independent executable" do
      expect(checks.binary_program?(elf("static_pie"))).to be true
    end

    it "is false for a shared library" do
      expect(checks.binary_program?(elf("libhello.so.0"))).to be false
    end
  end

  describe "#check_prebuilt_npm_binaries" do
    # A keg's binaries are enumerated by the macOS and Linux `Keg` extensions,
    # so there is nothing for the check to look at on a generic OS.
    before { skip "Binary enumeration is OS-specific." if !OS.mac? && !OS.linux? }

    it "reports an executable that is byte-identical to a downloaded package file" do
      binary = install_at "lib/node_modules/foo/node_modules/foo-darwin-arm64/foo"
      cache_package({ "package/foo" => binary.binread }, name: "foo-darwin-arm64")

      expect(checks.check_prebuilt_npm_binaries(f))
        .to include("foo-darwin-arm64/foo\t(package/foo of foo-darwin-arm64)")
    end

    it "ignores a binary matched by an allowlisted path" do
      binary = install_at "lib/node_modules/foo/node_modules/foo-darwin-arm64/foo"
      cache_package({ "package/foo" => binary.binread })
      allow(tap).to receive(:audit_exception).with(:prebuilt_binary_allowlist, f.name)
                                             .and_return(["libexec/lib/node_modules/foo/**/foo"])

      expect(checks.check_prebuilt_npm_binaries(f)).to be_nil
    end

    it "still reports a binary an allowlisted path does not cover" do
      binary = install_at "lib/node_modules/foo/node_modules/foo-darwin-arm64/foo"
      cache_package({ "package/foo" => binary.binread })
      allow(tap).to receive(:audit_exception).with(:prebuilt_binary_allowlist, f.name)
                                             .and_return(["libexec/lib/node_modules/other/**"])

      expect(checks.check_prebuilt_npm_binaries(f)).not_to be_nil
    end

    it "ignores a record a later tombstone deleted" do
      binary = install_at "lib/node_modules/foo/node_modules/dl-darwin-arm64/dl"
      cache_package({ "package/dl" => binary.binread }, name: "dl-darwin-arm64")
      append_index_record(key: download_key("dl-darwin-arm64"), integrity: nil)

      expect(checks.check_prebuilt_npm_binaries(f)).to be_nil
    end

    it "keeps reading past a cache line that is not an object" do
      binary = install_at "lib/node_modules/foo/node_modules/dl-darwin-arm64/dl"
      index = npm_cache/"index-v5/00/00/index"
      index.dirname.mkpath
      index.open("a") { |io| io.puts("0000\tnull") }
      cache_package({ "package/dl" => binary.binread }, name: "dl-darwin-arm64")

      expect(checks.check_prebuilt_npm_binaries(f)).to include("dl-darwin-arm64/dl")
    end

    it "ignores an executable npm packed from the build rather than downloaded" do
      binary = install_at "lib/node_modules/foo/bin/foo"
      cache_package({ "package/bin/foo" => binary.binread }, name: "foo", keys: [local_key("foo")])

      expect(checks.check_prebuilt_npm_binaries(f)).to be_nil
    end

    it "reports an executable from a package npm recorded downloading" do
      binary = install_at "lib/node_modules/foo/node_modules/dl-darwin-arm64/dl"
      cache_package({ "package/dl" => binary.binread }, name: "dl-darwin-arm64")

      expect(checks.check_prebuilt_npm_binaries(f)).to include("dl-darwin-arm64/dl\t(package/dl of dl-darwin-arm64)")
    end

    it "inspects content that both a local and a downloaded record point at" do
      binary = install_at "lib/node_modules/foo/node_modules/both-darwin-arm64/both"
      cache_package({ "package/both" => binary.binread }, name: "both-darwin-arm64",
                                                          keys: [local_key("both-darwin-arm64"),
                                                                 "make-fetch-happen:request-cache:https://registry.npmjs.org/both/-/both-1.0.0.tgz"])

      expect(checks.check_prebuilt_npm_binaries(f)).to include("both-darwin-arm64/both")
    end

    it "ignores an executable the build produced" do
      install_at "lib/node_modules/foo/bin/foo"
      cache_package({ "package/foo" => "not the same bytes" })

      expect(checks.check_prebuilt_npm_binaries(f)).to be_nil
    end

    it "ignores a helper shipped beside a downloaded native addon" do
      binary = install_at "lib/node_modules/foo/node_modules/node-pty/prebuilds/spawn-helper"
      addon = install_at("lib/node_modules/foo/node_modules/node-pty/prebuilds/pty.node", library)
      cache_package({ "package/prebuilds/spawn-helper" => binary.binread,
                      "package/prebuilds/pty.node"     => addon.binread })

      expect(checks.check_prebuilt_npm_binaries(f)).to be_nil
    end

    it "reports a helper beside a native addon the build compiled" do
      binary = install_at "lib/node_modules/foo/node_modules/node-pty/prebuilds/spawn-helper"
      install_at("lib/node_modules/foo/node_modules/node-pty/prebuilds/pty.node", library)
      cache_package({ "package/prebuilds/spawn-helper" => binary.binread })

      expect(checks.check_prebuilt_npm_binaries(f)).to include("node-pty/prebuilds/spawn-helper")
    end

    it "ignores shared libraries" do
      binary = install_at("lib/node_modules/foo/node_modules/bar/#{library_name}", library)
      cache_package({ "package/#{library_name}" => binary.binread })

      expect(checks.check_prebuilt_npm_binaries(f)).to be_nil
    end

    it "does nothing when npm downloaded nothing" do
      install_at "lib/node_modules/foo/node_modules/foo-darwin-arm64/foo"

      expect(checks.check_prebuilt_npm_binaries(f)).to be_nil
    end

    it "ignores allowlisted formulae" do
      binary = install_at "lib/node_modules/foo/node_modules/foo-darwin-arm64/foo"
      cache_package({ "package/foo" => binary.binread })
      allow(tap).to receive(:audit_exception).with(:prebuilt_binary_allowlist, f.name).and_return(true)

      expect(checks.check_prebuilt_npm_binaries(f)).to be_nil
    end

    it "applies the allowlist to a versioned formula from its unversioned name" do
      versioned = formula("cellar_checks_test@2") do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      versioned.prefix.mkpath
      allow(versioned).to receive(:tap).and_return(tap)
      allow(tap).to receive(:audit_exception).with(:prebuilt_binary_allowlist, "cellar_checks_test")
                                             .and_return(true)
      target = versioned.libexec/"lib/node_modules/foo/node_modules/foo-darwin-arm64/foo"
      target.dirname.mkpath
      cp executable, target
      cache_package({ "package/foo" => target.binread })

      expect(checker_class.new(versioned).check_prebuilt_npm_binaries(versioned)).to be_nil
    end
  end
end
