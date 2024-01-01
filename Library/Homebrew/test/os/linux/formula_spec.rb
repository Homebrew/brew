# frozen_string_literal: true

require "test/support/fixtures/testball"
require "formula"

describe Formula do
  describe "#uses_from_macos" do
    before do
      allow(OS).to receive(:mac?).and_return(false)
    end

    it "acts like #depends_on" do
      f = formula "foo" do
        url "foo-1.0"

        uses_from_macos("foo")
      end

      expect(f.class.stable.deps.first.name).to eq("foo")
      expect(f.class.head.deps.first.name).to eq("foo")
    end

    it "ignores OS version specifications" do
      f = formula "foo" do
        url "foo-1.0"

        uses_from_macos "foo", since: :mojave
      end

      expect(f.class.stable.deps.first.name).to eq("foo")
      expect(f.class.head.deps.first.name).to eq("foo")
    end
  end

  describe "#on_linux" do
    it "adds a dependency on Linux only" do
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
      expect(f.class.stable.deps[1].name).to eq("hello_linux")
      expect(f.class.stable.deps[2]).to be_nil
    end

    it "adds a patch on Linux only" do
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
      expect(f.patchlist.first.url).to eq("patch_linux")
    end

    it "uses on_linux within a resource block" do
      f = formula do
        homepage "https://brew.sh"

        url "https://brew.sh/test-0.1.tbz"
        sha256 TEST_SHA256

        resource "test_resource" do
          on_linux do
            url "on_linux"
          end
        end
      end
      expect(f.resources.length).to eq(1)
      expect(f.resources.first.url).to eq("on_linux")
    end
  end

  describe "#shared_library" do
    it "generates a shared library string" do
      f = Testball.new
      expect(f.shared_library("foobar")).to eq("foobar.so")
      expect(f.shared_library("foobar", 2)).to eq("foobar.so.2")
      expect(f.shared_library("foobar", nil)).to eq("foobar.so")
      expect(f.shared_library("foobar", "*")).to eq("foobar.so{,.*}")
      expect(f.shared_library("*")).to eq("*.so{,.*}")
      expect(f.shared_library("*", 2)).to eq("*.so.2")
      expect(f.shared_library("*", nil)).to eq("*.so{,.*}")
      expect(f.shared_library("*", "*")).to eq("*.so{,.*}")
    end
  end
end
