# frozen_string_literal: false
=begin
 external service
        Copyright (c) 2000,2002 Masatoshi SEKI
=end

require_relative 'drb'
require 'monitor'

module DRb
  class ExtServ
    include MonitorMixin
    include DRbUndumped

    def initialize(there, name, server=nil)
      super()
      @server = server || DRb::primary_server
      @name = name
      ro = DRbObject.new(nil, there)
      synchronize do
        @invoker = ro.register(name, DRbObject.new(self, @server.uri))
      end
    end
    attr_reader :server

    def front
      DRbObject.new(nil, @server.uri)
    end

    def stop_service
      synchronize do
        @invoker.unregister(@name)
        server = @server
        @server = nil
        server.stop_service
        true
      end
    end

    def alive?
      @server ? @server.alive? : false
    end
  end
end
