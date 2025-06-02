# This is a simple tool to enable the object allocation tracer.
# When you have an object of unknown provenance, you can use this
# to investigate where the object in question is created.
#
# = Important notice
#
# This is only for debugging purpose. Do not use this in production.
# Require'ing this file immediately starts tracing the object allocation,
# which brings a large performance overhead.
#
# = Usage
#
# 1. Add `require "objspace/trace"` into your code (or add `-robjspace/trace` into the command line)
# 2. `p obj` will show the allocation site of `obj`
#
# Note: This redefines `Kernel#p` method, but not `Object#inspect`.
#
# = Examples
#
#   1: require "objspace/trace"
#   2:
#   3: obj = "str"
#   4:
#   5: p obj  #=> "str" @ test.rb:3

require 'objspace.so'

module Kernel
  remove_method :p
  define_method(:p) do |*objs|
    objs.each do |obj|
      file = ObjectSpace.allocation_sourcefile(obj)
      line = ObjectSpace.allocation_sourceline(obj)
      if file
        puts "#{ obj.inspect } @ #{ file }:#{ line }"
      else
        puts obj.inspect
      end
    end
  end
end

ObjectSpace.trace_object_allocations_start

warn "objspace/trace is enabled"
