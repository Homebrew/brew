# frozen_string_literal: true

require "mkmf"

if %w[ruby truffleruby].include?(RUBY_ENGINE)
  have_func "fdatasync", "unistd.h"

  unless RUBY_PLATFORM.match?(/mswin|mingw|cygwin/)
    append_cppflags ["-D_GNU_SOURCE"] # Needed of O_NOATIME
  end

  append_cflags ["-O3", "-std=c99"]

  # ruby.h has some -Wpedantic fails in some cases
  # (e.g. https://github.com/Shopify/bootsnap/issues/15)
  unless ["0", "", nil].include?(ENV["BOOTSNAP_PEDANTIC"])
    append_cflags([
      "-Wall",
      "-Werror",
      "-Wextra",
      "-Wpedantic",

      "-Wno-unused-parameter", # VALUE self has to be there but we don't care what it is.
      "-Wno-keyword-macro", # hiding return
      "-Wno-gcc-compat", # ruby.h 2.6.0 on macos 10.14, dunno
      "-Wno-compound-token-split-by-macro",
    ])
  end

  create_makefile("bootsnap/bootsnap")
else
  File.write("Makefile", dummy_makefile($srcdir).join)
end
