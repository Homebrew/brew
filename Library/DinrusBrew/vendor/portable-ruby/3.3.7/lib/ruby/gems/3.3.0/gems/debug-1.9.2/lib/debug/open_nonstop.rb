# frozen_string_literal: true
#
# Open the door for the debugger to connect.
# Unlike debug/open, it does not stop at the beginning of the program.
# Users can connect to debuggee program with "rdbg --attach" option or
# VSCode attach type.
#
# If RUBY_DEBUG_PORT envval is provided (digits), open TCP/IP port.
# Otherwise, UNIX domain socket is used.
#

require_relative 'session'
return unless defined?(DEBUGGER__)

DEBUGGER__.open(nonstop: true)
