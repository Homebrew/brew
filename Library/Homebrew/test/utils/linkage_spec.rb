# frozen_string_literal: true

require "utils/linkage"

RSpec.describe Utils do
  suffix = OS.mac? ? ".dylib" : ".so"

  describe "::binary_linked_to_library?", :integration_test do
    before do
      install_test_formula "testball-linkage", <<~RUBY
        def install
          (buildpath/"foo.h").write "void foo();"
          (buildpath/"foo.c").write <<~C
            #include <stdio.h>
            #include "foo.h"
            void foo() { printf("foo\\\\n"); }
          C
          (buildpath/"bar.c").write <<~C
            #include <stdio.h>
            void bar() { printf("bar\\\\n"); }
          C
          (buildpath/"test.c").write <<~C
            #include "foo.h"
            int main() { foo(); return 0; }
          C
          system ENV.cc, "-c", "-fpic", "foo.c"
          system ENV.cc, "-c", "-fpic", "bar.c"
          dll_flag = OS.mac? ? "-dynamiclib" : "-shared"
          system ENV.cc, dll_flag, "-o", shared_library("libbrewfoo"), "foo.o"
          system ENV.cc, dll_flag, "-o", shared_library("libbrewbar"), "bar.o"
          lib.install shared_library("libbrewfoo"), shared_library("libbrewbar")
          system ENV.cc, "-o", "brewtest", "test.c", "-L\#{lib}", "-lbrewfoo"
          bin.install "brewtest"
        end
      RUBY
    end

    it "returns true if the binary is linked to the library" do
      f = Formula["testball-linkage"]
      result = described_class.binary_linked_to_library?(f.bin/"brewtest",
                                                         f.lib/"libbrewfoo#{suffix}", HOMEBREW_CELLAR)
      expect(result).to be true
    end

    it "returns false if the binary is not linked to the library" do
      f = Formula["testball-linkage"]
      result = described_class.binary_linked_to_library?(f.bin/"brewtest",
                                                         f.lib/"libbrewbar#{suffix}", HOMEBREW_CELLAR)
      expect(result).to be false
    end
  end
end
