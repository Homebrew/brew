#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

pid = ARGV[0]&.to_i
raise "Missing `pid` argument!" unless pid

require "fiddle"

# Canonically, this is a part of libproc.dylib. libproc is however just a symlink to libSystem
# and some security tools seem to not support aliases from the dyld shared cache and incorrectly flag this.
libproc = Fiddle.dlopen("/usr/lib/libSystem.B.dylib")

libproc_proc_pidpath_function = Fiddle::Function.new(
  libproc["proc_pidpath"],
  [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T],
  Fiddle::TYPE_INT,
)

# We have to allocate a (char) buffer of exactly `PROC_PIDPATHINFO_MAXSIZE` to use `proc_pidpath`
# From `include/sys/proc_info.h`, PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN
# From `include/sys/param.h`, MAXPATHLEN = PATH_MAX
# From `include/sys/syslimits.h`, PATH_MAX = 1024
# https://github.com/apple-oss-distributions/xnu/blob/e3723e1f17661b24996789d8afc084c0c3303b26/libsyscall/wrappers/libproc/libproc.c#L268-L275
buffer_size = 4 * 1024 # PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN
buffer = "\0" * buffer_size
pointer_to_buffer = Fiddle::Pointer.to_ptr(buffer)

# `proc_pidpath` returns a positive value on success. See:
# https://stackoverflow.com/a/8149198
# https://github.com/chromium/chromium/blob/86df41504a235f9369f6f53887da12a718a19db4/base/process/process_handle_mac.cc#L37-L44
# https://github.com/apple-oss-distributions/xnu/blob/e3723e1f17661b24996789d8afc084c0c3303b26/libsyscall/wrappers/libproc/libproc.c#L263-L283
return_value = libproc_proc_pidpath_function.call(pid, pointer_to_buffer, buffer_size)
raise "Call to `proc_pidpath` failed! `proc_pidpath` returned #{return_value}." unless return_value.positive?

puts pointer_to_buffer.to_s.strip
