# frozen_string_literal: true

require 'socket'
require 'resolv'

class << IPSocket
  # :stopdoc:
  alias original_resolv_getaddress getaddress
  # :startdoc:
  def getaddress(host)
    begin
      return Resolv.getaddress(host).to_s
    rescue Resolv::ResolvError
      raise SocketError, "Hostname not known: #{host}"
    end
  end
end

class TCPSocket < IPSocket
  # :stopdoc:
  alias original_resolv_initialize initialize
  # :startdoc:
  def initialize(host, serv, *rest)
    rest[0] = IPSocket.getaddress(rest[0]) if rest[0]
    original_resolv_initialize(IPSocket.getaddress(host), serv, *rest)
  end
end

class UDPSocket < IPSocket
  # :stopdoc:
  alias original_resolv_bind bind
  # :startdoc:
  def bind(host, port)
    host = IPSocket.getaddress(host) if host != ""
    original_resolv_bind(host, port)
  end

  # :stopdoc:
  alias original_resolv_connect connect
  # :startdoc:
  def connect(host, port)
    original_resolv_connect(IPSocket.getaddress(host), port)
  end

  # :stopdoc:
  alias original_resolv_send send
  # :startdoc:
  def send(mesg, flags, *rest)
    if rest.length == 2
      host, port = rest
      begin
        addrs = Resolv.getaddresses(host)
      rescue Resolv::ResolvError
        raise SocketError, "Hostname not known: #{host}"
      end
      addrs[0...-1].each {|addr|
        begin
          return original_resolv_send(mesg, flags, addr, port)
        rescue SystemCallError
        end
      }
      original_resolv_send(mesg, flags, addrs[-1], port)
    else
      original_resolv_send(mesg, flags, *rest)
    end
  end
end

class SOCKSSocket < TCPSocket
  # :stopdoc:
  alias original_resolv_initialize initialize
  # :startdoc:
  def initialize(host, serv)
    original_resolv_initialize(IPSocket.getaddress(host), port)
  end
end if defined? SOCKSSocket
