class Gem::Net::HTTP::Persistent::Pool < Bundler::ConnectionPool # :nodoc:

  attr_reader :available # :nodoc:
  attr_reader :key # :nodoc:

  def initialize(options = {}, &block)
    super

    @available = Gem::Net::HTTP::Persistent::TimedStackMulti.new(@size, &block)
    @key = "current-#{@available.object_id}"
  end

  def checkin net_http_args
    if net_http_args.is_a?(Hash) && net_http_args.size == 1 && net_http_args[:force]
      # Bundler::ConnectionPool 2.4+ calls `checkin(force: true)` after fork.
      # When this happens, we should remove all connections from Thread.current
      if stacks = Thread.current[@key]
        stacks.each do |http_args, connections|
          connections.each do |conn|
            @available.push conn, connection_args: http_args
          end
          connections.clear
        end
      end
    else
      stack = Thread.current[@key][net_http_args] ||= []

      raise Bundler::ConnectionPool::Error, 'no connections are checked out' if
        stack.empty?

      conn = stack.pop

      if stack.empty?
        @available.push conn, connection_args: net_http_args

        Thread.current[@key].delete(net_http_args)
        Thread.current[@key] = nil if Thread.current[@key].empty?
      end
    end
    nil
  end

  def checkout net_http_args
    stacks = Thread.current[@key] ||= {}
    stack  = stacks[net_http_args] ||= []

    if stack.empty? then
      conn = @available.pop connection_args: net_http_args
    else
      conn = stack.last
    end

    stack.push conn

    conn
  end

  def shutdown
    Thread.current[@key] = nil
    super
  end
end

require_relative 'timed_stack_multi'

