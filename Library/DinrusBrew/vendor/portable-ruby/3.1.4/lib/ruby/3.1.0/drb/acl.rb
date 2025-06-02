# frozen_string_literal: false
# Copyright (c) 2000,2002,2003 Masatoshi SEKI
#
# acl.rb is copyrighted free software by Masatoshi SEKI.
# You can redistribute it and/or modify it under the same terms as Ruby.

require 'ipaddr'

##
# Simple Access Control Lists.
#
# Access control lists are composed of "allow" and "deny" halves to control
# access.  Use "all" or "*" to match any address.  To match a specific address
# use any address or address mask that IPAddr can understand.
#
# Example:
#
#   list = %w[
#     deny all
#     allow 192.168.1.1
#     allow ::ffff:192.168.1.2
#     allow 192.168.1.3
#   ]
#
#   # From Socket#peeraddr, see also ACL#allow_socket?
#   addr = ["AF_INET", 10, "lc630", "192.168.1.3"]
#
#   acl = ACL.new
#   p acl.allow_addr?(addr) # => true
#
#   acl = ACL.new(list, ACL::DENY_ALLOW)
#   p acl.allow_addr?(addr) # => true

class ACL

  ##
  # The current version of ACL

  VERSION=["2.0.0"]

  ##
  # An entry in an ACL

  class ACLEntry

    ##
    # Creates a new entry using +str+.
    #
    # +str+ may be "*" or "all" to match any address, an IP address string
    # to match a specific address, an IP address mask per IPAddr, or one
    # containing "*" to match part of an IPv4 address.
    #
    # IPAddr::InvalidPrefixError may be raised when an IP network
    # address with an invalid netmask/prefix is given.

    def initialize(str)
      if str == '*' or str == 'all'
        @pat = [:all]
      elsif str.include?('*')
        @pat = [:name, dot_pat(str)]
      else
        begin
          @pat = [:ip, IPAddr.new(str)]
        rescue IPAddr::InvalidPrefixError
          # In this case, `str` shouldn't be a host name pattern
          # because it contains a slash.
          raise
        rescue ArgumentError
          @pat = [:name, dot_pat(str)]
        end
      end
    end

    private

    ##
    # Creates a regular expression to match IPv4 addresses

    def dot_pat_str(str)
      list = str.split('.').collect { |s|
        (s == '*') ? '.+' : s
      }
      list.join("\\.")
    end

    private

    ##
    # Creates a Regexp to match an address.

    def dot_pat(str)
      /\A#{dot_pat_str(str)}\z/
    end

    public

    ##
    # Matches +addr+ against this entry.

    def match(addr)
      case @pat[0]
      when :all
        true
      when :ip
        begin
          ipaddr = IPAddr.new(addr[3])
          ipaddr = ipaddr.ipv4_mapped if @pat[1].ipv6? && ipaddr.ipv4?
        rescue ArgumentError
          return false
        end
        (@pat[1].include?(ipaddr)) ? true : false
      when :name
        (@pat[1] =~ addr[2]) ? true : false
      else
        false
      end
    end
  end

  ##
  # A list of ACLEntry objects.  Used to implement the allow and deny halves
  # of an ACL

  class ACLList

    ##
    # Creates an empty ACLList

    def initialize
      @list = []
    end

    public

    ##
    # Matches +addr+ against each ACLEntry in this list.

    def match(addr)
      @list.each do |e|
        return true if e.match(addr)
      end
      false
    end

    public

    ##
    # Adds +str+ as an ACLEntry in this list

    def add(str)
      @list.push(ACLEntry.new(str))
    end

  end

  ##
  # Default to deny

  DENY_ALLOW = 0

  ##
  # Default to allow

  ALLOW_DENY = 1

  ##
  # Creates a new ACL from +list+ with an evaluation +order+ of DENY_ALLOW or
  # ALLOW_DENY.
  #
  # An ACL +list+ is an Array of "allow" or "deny" and an address or address
  # mask or "all" or "*" to match any address:
  #
  #   %w[
  #     deny all
  #     allow 192.0.2.2
  #     allow 192.0.2.128/26
  #   ]

  def initialize(list=nil, order = DENY_ALLOW)
    @order = order
    @deny = ACLList.new
    @allow = ACLList.new
    install_list(list) if list
  end

  public

  ##
  # Allow connections from Socket +soc+?

  def allow_socket?(soc)
    allow_addr?(soc.peeraddr)
  end

  public

  ##
  # Allow connections from addrinfo +addr+?  It must be formatted like
  # Socket#peeraddr:
  #
  #   ["AF_INET", 10, "lc630", "192.0.2.1"]

  def allow_addr?(addr)
    case @order
    when DENY_ALLOW
      return true if @allow.match(addr)
      return false if @deny.match(addr)
      return true
    when ALLOW_DENY
      return false if @deny.match(addr)
      return true if @allow.match(addr)
      return false
    else
      false
    end
  end

  public

  ##
  # Adds +list+ of ACL entries to this ACL.

  def install_list(list)
    i = 0
    while i < list.size
      permission, domain = list.slice(i,2)
      case permission.downcase
      when 'allow'
        @allow.add(domain)
      when 'deny'
        @deny.add(domain)
      else
        raise "Invalid ACL entry #{list}"
      end
      i += 2
    end
  end

end
