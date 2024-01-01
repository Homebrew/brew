# typed: strict
# frozen_string_literal: true

require "socket"

module Homebrew
  # Helper function for finding a free port.
  #
  # @api private
  module FreePort
    # Returns a free port.
    # @api public
    sig { returns(Integer) }
    def free_port
      server = TCPServer.new 0
      _, port, = server.addr
      server.close

      port
    end
  end
end
