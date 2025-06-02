# frozen_string_literal: true
##
# A connection "pool" that only manages one connection for now.  Provides
# thread safe `checkout` and `checkin` methods.  The pool consists of one
# connection that corresponds to `http_args`.  This class is private, do not
# use it.

class Gem::Request::HTTPPool # :nodoc:
  attr_reader :cert_files, :proxy_uri

  def initialize(http_args, cert_files, proxy_uri)
    @http_args  = http_args
    @cert_files = cert_files
    @proxy_uri  = proxy_uri
    @queue      = Thread::SizedQueue.new 1
    @queue << nil
  end

  def checkout
    @queue.pop || make_connection
  end

  def checkin(connection)
    @queue.push connection
  end

  def close_all
    until @queue.empty?
      if (connection = @queue.pop(true)) && connection.started?
        connection.finish
      end
    end
    @queue.push(nil)
  end

  private

  def make_connection
    setup_connection Gem::Request::ConnectionPools.client.new(*@http_args)
  end

  def setup_connection(connection)
    connection.start
    connection
  end
end
