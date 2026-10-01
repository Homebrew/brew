# typed: true
# frozen_string_literal: true

require "test/support/fixtures/testball"
require "formula"

RSpec.describe Formula do
  describe "#change_dylib_id" do
    subject(:f) do
      formula "dylib-id-test" do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
    end

    let(:dylib) { f.lib/"libfoo.1.dylib" }

    before do
      dylib.dirname.mkpath
      FileUtils.touch dylib
    end

    after { f.prefix.rmtree }

    it "uses the explicit source and dylib ID" do
      unversioned_dylib = f.lib/"libfoo.dylib"
      FileUtils.ln_s dylib, unversioned_dylib
      expect(Homebrew::InstallSteps).to receive(:change_dylib_id)
        .with(unversioned_dylib, f.opt_lib/"libfoo.dylib", resolve_source: false)

      f.change_dylib_id unversioned_dylib, f.opt_lib/"libfoo.dylib"
    end

    it "can resolve the source symlink and codesigns on ARM" do
      unversioned_dylib = f.lib/"libfoo.dylib"
      FileUtils.ln_s dylib, unversioned_dylib
      expect(Homebrew::InstallSteps).to receive(:change_dylib_id)
        .with(unversioned_dylib, "@rpath/libfoo.dylib", resolve_source: true)

      f.change_dylib_id unversioned_dylib, "@rpath/libfoo.dylib", resolve_source: true
    end
  end

  describe "#uses_from_macos" do
    before do
      allow(OS).to receive(:mac?).and_return(true)
      allow(OS::Mac).to receive(:version).and_return(MacOSVersion.from_symbol(:sonoma))
    end

    it "adds a macOS dependency to all specs if the OS version meets requirements" do
      f = formula "foo" do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"

        uses_from_macos("foo", since: :big_sur)
      end

      expect(f.class.stable.deps).to be_empty
      expect(f.class.head.deps).to be_empty
      expect(f.class.stable.declared_deps).not_to be_empty
      expect(f.class.head.declared_deps).not_to be_empty
      expect(f.class.stable.declared_deps.first.name).to eq("foo")
      expect(f.class.head.declared_deps.first.name).to eq("foo")
    end

    it "adds a dependency to any spec if the OS version doesn't meet requirements" do
      f = formula "foo" do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"

        uses_from_macos("foo", since: :tahoe)
      end

      expect(f.class.stable.deps).not_to be_empty
      expect(f.class.head.deps).not_to be_empty
      expect(f.class.stable.deps.first.name).to eq("foo")
      expect(f.class.head.deps.first.name).to eq("foo")
      expect(f.class.stable.declared_deps).not_to be_empty
      expect(f.class.head.declared_deps).not_to be_empty
    end
  end

  describe "#on_macos" do
    it "adds a dependency on macos only" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        homepage "https://brew.sh"

        url "https://brew.sh/test-0.1.tbz"
        sha256 TEST_SHA256

        depends_on "hello_both"

        on_macos do
          depends_on "hello_macos"
        end

        on_linux do
          depends_on "hello_linux"
        end
      end

      expect(f.class.stable.deps[0].name).to eq("hello_both")
      expect(f.class.stable.deps[1].name).to eq("hello_macos")
      expect(f.class.stable.deps[2]).to be_nil
    end

    it "adds a patch on Mac only" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        homepage "https://brew.sh"

        url "https://brew.sh/test-0.1.tbz"
        sha256 TEST_SHA256

        patch do
          on_macos do
            url "patch_macos"
          end

          on_linux do
            url "patch_linux"
          end
        end
      end

      expect(f.patchlist.length).to eq(1)
      expect(f.patchlist.first.strip).to eq(:p1)
      expect(f.patchlist.first.url).to eq("patch_macos")
    end

    it "uses on_macos within a resource block" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        homepage "https://brew.sh"

        url "https://brew.sh/test-0.1.tbz"
        sha256 TEST_SHA256

        resource "test_resource" do
          on_macos do
            url "resource_macos"
          end
        end
      end
      expect(f.resources.length).to eq(1)
      expect(f.resources.first.url).to eq("resource_macos")
    end
  end

  describe "#common_sandbox_env" do
    it "runs Java headless because the sandbox denies WindowServer access" do
      f = Testball.new
      expect(f.common_sandbox_env(mktmpdir)[:_JAVA_OPTIONS]).to eq(
        "-Duser.home=#{Homebrew::PackageManagerCache.path("java_cache")} " \
        "-Djava.io.tmpdir=#{HOMEBREW_TEMP} -Djava.awt.headless=true",
      )
    end
  end

  describe "#test_sandbox_env" do
    it "tells the java launcher to skip jar splash screens" do
      f = Testball.new
      expect(f.test_sandbox_env(mktmpdir)[:JDK_JAVA_OPTIONS]).to eq("-Djava.awt.headless=true")
    end

    it "keeps the common sandbox environment" do
      f = Testball.new
      testpath = mktmpdir
      expect(f.test_sandbox_env(testpath)).to include(
        f.common_sandbox_env(testpath).except(:GIT_CONFIG_GLOBAL),
      )
    end
  end

  describe "#shared_library" do
    it "generates a shared library string" do
      f = Testball.new
      expect(f.shared_library("foobar")).to eq("foobar.dylib")
      expect(f.shared_library("foobar", 2)).to eq("foobar.2.dylib")
      expect(f.shared_library("foobar", nil)).to eq("foobar.dylib")
      expect(f.shared_library("foobar", "*")).to eq("foobar{,.*}.dylib")
      expect(f.shared_library("*")).to eq("*.dylib")
      expect(f.shared_library("*", 2)).to eq("*.2.dylib")
      expect(f.shared_library("*", nil)).to eq("*.dylib")
      expect(f.shared_library("*", "*")).to eq("*.dylib")
    end
  end
end
