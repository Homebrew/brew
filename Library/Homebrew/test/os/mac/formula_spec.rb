# frozen_string_literal: true

require "test/support/fixtures/testball"
require "formula"

describe Formula do
  describe "#uses_from_macos" do
    before do
      allow(OS).to receive(:mac?).and_return(true)
      allow(OS::Mac).to receive(:version).and_return(MacOSVersion.from_symbol(:sierra))
    end

    it "adds a macOS dependency to all specs if the OS version meets requirements" do
      f = formula "foo" do
        url "foo-1.0"

        uses_from_macos("foo", since: :el_capitan)
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
        url "foo-1.0"

        uses_from_macos("foo", since: :high_sierra)
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
