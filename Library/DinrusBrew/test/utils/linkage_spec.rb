# frozen_string_literal: true

require "utils/linkage"

RSpec.describe Utils do
  [:needs_macos, :needs_linux].each do |needs_os|
    describe "::binary_linked_to_library?", needs_os do
      suffix = OS.mac? ? ".dylib" : ".so"

      before do
        mktmpdir do |dir|
          (dir/"foo.h").write "void foo();"
          (dir/"foo.c").write <<~C
            #include <stdio.h>
            #include "foo.h"
            void foo() { printf("foo\\\\n"); }
          C
          (dir/"bar.c").write <<~C
            #include <stdio.h>
            void bar() { printf("bar\\\\n"); }
          C
          (dir/"test.c").write <<~C
            #include "foo.h"
            int main() { foo(); return 0; }
          C

          system "cc", "-c", "-fpic", dir/"foo.c", "-o", dir/"foo.o"
          system "cc", "-c", "-fpic", dir/"bar.c", "-o", dir/"bar.o"
          dll_flag = OS.mac? ? "-dynamiclib" : "-shared"
          (DINRUSBREW_PREFIX/"lib").mkdir
          system "cc", dll_flag, "-o", DINRUSBREW_PREFIX/"lib/libbrewfoo#{suffix}", dir/"foo.o"
          system "cc", dll_flag, "-o", DINRUSBREW_PREFIX/"lib/libbrewbar#{suffix}", dir/"bar.o"
          rpath_flag = "-Wl,-rpath,#{DINRUSBREW_PREFIX}/lib" if OS.linux?
          system "cc", "-o", dir/"brewtest", dir/"test.c", *rpath_flag, "-L#{DINRUSBREW_PREFIX/"lib"}", "-lbrewfoo"
          (DINRUSBREW_PREFIX/"bin").install dir/"brewtest"
        end
      end

      it "returns true if the binary is linked to the library" do
        result = described_class.binary_linked_to_library?(DINRUSBREW_PREFIX/"bin/brewtest",
                                                           DINRUSBREW_PREFIX/"lib/libbrewfoo#{suffix}")
        expect(result).to be true
      end

      it "returns false if the binary is not linked to the library" do
        result = described_class.binary_linked_to_library?(DINRUSBREW_PREFIX/"bin/brewtest",
                                                           DINRUSBREW_PREFIX/"lib/libbrewbar#{suffix}")
        expect(result).to be false
      end
    end
  end
end
