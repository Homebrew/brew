class Bundler::Persistent::Net::HTTP::Persistent::Pool < Bundler::ConnectionPool # :nodoc:

  attr_reader :available # :nodoc:
  attr_reader :key # :nodoc:

  def initialize(options = {}, &block)
    super

    @available = Bundler::Persistent::Net::HTTP::Persistent::TimedStackMulti.new(@size, &block)
    @key = "current-#{@available.object_id}"
  end

  def checkin net_http_args
    stack = Thread.current[@key][net_http_args] ||= []

    raise Bundler::ConnectionPool::Error, 'no connections are checked out' if
      stack.empty?

    conn = stack.pop

    if stack.empty?
      @available.push conn, connection_args: net_http_args

      Thread.current[@key].delete(net_http_args)
      Thread.current[@key] = nil if Thread.current[@key].empty?
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

