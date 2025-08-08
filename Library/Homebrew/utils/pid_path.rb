#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require "fiddle"

libproc = Fiddle.dlopen("/usr/lib/libproc.dylib")

proc_pidpath = Fiddle::Function.new(
  libproc["proc_pidpath"],
  [Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT32_T],
  Fiddle::TYPE_INT,
)

pid = ARGV[0]&.to_i
exit 1 unless pid

bufsize = 4 * 1024 # PROC_PIDPATHINFO_MAXSIZE = 4 * MAXPATHLEN
buf = "\0" * bufsize
ptr = Fiddle::Pointer.to_ptr(buf)

ret = proc_pidpath.call(pid, ptr, bufsize)
puts ptr.to_s.strip if ret.positive?
