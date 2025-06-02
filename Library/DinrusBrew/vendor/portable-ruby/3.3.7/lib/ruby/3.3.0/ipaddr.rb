# frozen_string_literal: true
#
# ipaddr.rb - A class to manipulate an IP address
#
# Copyright (c) 2002 Hajimu UMEMOTO <ume@mahoroba.org>.
# Copyright (c) 2007, 2009, 2012 Akinori MUSHA <knu@iDaemons.org>.
# All rights reserved.
#
# You can redistribute and/or modify it under the same terms as Ruby.
#
# $Id$
#
# Contact:
#   - Akinori MUSHA <knu@iDaemons.org> (current maintainer)
#
# TODO:
#   - scope_id support
#
require 'socket'

# IPAddr provides a set of methods to manipulate an IP address.  Both IPv4 and
# IPv6 are supported.
#
# == Example
#
#   require 'ipaddr'
#
#   ipaddr1 = IPAddr.new "3ffe:505:2::1"
#
#   p ipaddr1                   #=> #<IPAddr: IPv6:3ffe:0505:0002:0000:0000:0000:0000:0001/ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff>
#
#   p ipaddr1.to_s              #=> "3ffe:505:2::1"
#
#   ipaddr2 = ipaddr1.mask(48)  #=> #<IPAddr: IPv6:3ffe:0505:0002:0000:0000:0000:0000:0000/ffff:ffff:ffff:0000:0000:0000:0000:0000>
#
#   p ipaddr2.to_s              #=> "3ffe:505:2::"
#
#   ipaddr3 = IPAddr.new "192.168.2.0/24"
#
#   p ipaddr3                   #=> #<IPAddr: IPv4:192.168.2.0/255.255.255.0>

class IPAddr
  VERSION = "1.2.6"

  # 32 bit mask for IPv4
  IN4MASK = 0xffffffff
  # 128 bit mask for IPv6
  IN6MASK = 0xffffffffffffffffffffffffffffffff
  # Format string for IPv6
  IN6FORMAT = (["%.4x"] * 8).join(':').freeze

  # Regexp _internally_ used for parsing IPv4 address.
  RE_IPV4ADDRLIKE = %r{
    \A
    (\d+) \. (\d+) \. (\d+) \. (\d+)
    \z
  }x

  # Regexp _internally_ used for parsing IPv6 address.
  RE_IPV6ADDRLIKE_FULL = %r{
    \A
    (?:
      (?: [\da-f]{1,4} : ){7} [\da-f]{1,4}
    |
      ( (?: [\da-f]{1,4} : ){6} )
      (\d+) \. (\d+) \. (\d+) \. (\d+)
    )
    \z
  }xi

  # Regexp _internally_ used for parsing IPv6 address.
  RE_IPV6ADDRLIKE_COMPRESSED = %r{
    \A
    ( (?: (?: [\da-f]{1,4} : )* [\da-f]{1,4} )? )
    ::
    ( (?:
      ( (?: [\da-f]{1,4} : )* )
      (?:
        [\da-f]{1,4}
      |
        (\d+) \. (\d+) \. (\d+) \. (\d+)
      )
    )? )
    \z
  }xi

  # Generic IPAddr related error. Exceptions raised in this class should
  # inherit from Error.
  class Error < ArgumentError; end

  # Raised when the provided IP address is an invalid address.
  class InvalidAddressError < Error; end

  # Raised when the address family is invalid such as an address with an
  # unsupported family, an address with an inconsistent family, or an address
  # who's family cannot be determined.
  class AddressFamilyError < Error; end

  # Raised when the address is an invalid length.
  class InvalidPrefixError < InvalidAddressError; end

  # Returns the address family of this IP address.
  attr_reader :family

  # Creates a new ipaddr containing the given network byte ordered
  # string form of an IP address.
  def self.new_ntoh(addr)
    return new(ntop(addr))
  end

  # Convert a network byte ordered string form of an IP address into
  # human readable form.
  def self.ntop(addr)
    case addr.size
    when 4
      addr.unpack('C4').join('.')
    when 16
      IN6FORMAT % addr.unpack('n8')
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  # Returns a new ipaddr built by bitwise AND.
  def &(other)
    return self.clone.set(@addr & coerce_other(other).to_i)
  end

  # Returns a new ipaddr built by bitwise OR.
  def |(other)
    return self.clone.set(@addr | coerce_other(other).to_i)
  end

  # Returns a new ipaddr built by bitwise right-shift.
  def >>(num)
    return self.clone.set(@addr >> num)
  end

  # Returns a new ipaddr built by bitwise left shift.
  def <<(num)
    return self.clone.set(addr_mask(@addr << num))
  end

  # Returns a new ipaddr built by bitwise negation.
  def ~
    return self.clone.set(addr_mask(~@addr))
  end

  # Returns true if two ipaddrs are equal.
  def ==(other)
    other = coerce_other(other)
  rescue
    false
  else
    @family == other.family && @addr == other.to_i
  end

  # Returns a new ipaddr built by masking IP address with the given
  # prefixlen/netmask. (e.g. 8, 64, "255.255.255.0", etc.)
  def mask(prefixlen)
    return self.clone.mask!(prefixlen)
  end

  # Returns true if the given ipaddr is in the range.
  #
  # e.g.:
  #   require 'ipaddr'
  #   net1 = IPAddr.new("192.168.2.0/24")
  #   net2 = IPAddr.new("192.168.2.100")
  #   net3 = IPAddr.new("192.168.3.0")
  #   net4 = IPAddr.new("192.168.2.0/16")
  #   p net1.include?(net2)     #=> true
  #   p net1.include?(net3)     #=> false
  #   p net1.include?(net4)     #=> false
  #   p net4.include?(net1)     #=> true
  def include?(other)
    other = coerce_other(other)
    return false unless other.family == family
    begin_addr <= other.begin_addr && end_addr >= other.end_addr
  end
  alias === include?

  # Returns the integer representation of the ipaddr.
  def to_i
    return @addr
  end

  # Returns a string containing the IP address representation.
  def to_s
    str = to_string
    return str if ipv4?

    str.gsub!(/\b0{1,3}([\da-f]+)\b/i, '\1')
    loop do
      break if str.sub!(/\A0:0:0:0:0:0:0:0\z/, '::')
      break if str.sub!(/\b0:0:0:0:0:0:0\b/, ':')
      break if str.sub!(/\b0:0:0:0:0:0\b/, ':')
      break if str.sub!(/\b0:0:0:0:0\b/, ':')
      break if str.sub!(/\b0:0:0:0\b/, ':')
      break if str.sub!(/\b0:0:0\b/, ':')
      break if str.sub!(/\b0:0\b/, ':')
      break
    end
    str.sub!(/:{3,}/, '::')

    if /\A::(ffff:)?([\da-f]{1,4}):([\da-f]{1,4})\z/i =~ str
      str = sprintf('::%s%d.%d.%d.%d', $1, $2.hex / 256, $2.hex % 256, $3.hex / 256, $3.hex % 256)
    end

    str
  end

  # Returns a string containing the IP address representation in
  # canonical form.
  def to_string
    str = _to_string(@addr)

    if @family == Socket::AF_INET6
      str << zone_id.to_s
    end

    return str
  end

  # Returns a network byte ordered string form of the IP address.
  def hton
    case @family
    when Socket::AF_INET
      return [@addr].pack('N')
    when Socket::AF_INET6
      return (0..7).map { |i|
        (@addr >> (112 - 16 * i)) & 0xffff
      }.pack('n8')
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  # Returns true if the ipaddr is an IPv4 address.
  def ipv4?
    return @family == Socket::AF_INET
  end

  # Returns true if the ipaddr is an IPv6 address.
  def ipv6?
    return @family == Socket::AF_INET6
  end

  # Returns true if the ipaddr is a loopback address.
  def loopback?
    case @family
    when Socket::AF_INET
      @addr & 0xff000000 == 0x7f000000
    when Socket::AF_INET6
      @addr == 1
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  # Returns true if the ipaddr is a private address.  IPv4 addresses
  # in 10.0.0.0/8, 172.16.0.0/12 and 192.168.0.0/16 as defined in RFC
  # 1918 and IPv6 Unique Local Addresses in fc00::/7 as defined in RFC
  # 4193 are considered private. Private IPv4 addresses in the
  # IPv4-mapped IPv6 address range are also considered private.
  def private?
    case @family
    when Socket::AF_INET
      @addr & 0xff000000 == 0x0a000000 ||    # 10.0.0.0/8
        @addr & 0xfff00000 == 0xac100000 ||  # 172.16.0.0/12
        @addr & 0xffff0000 == 0xc0a80000     # 192.168.0.0/16
    when Socket::AF_INET6
      @addr & 0xfe00_0000_0000_0000_0000_0000_0000_0000 == 0xfc00_0000_0000_0000_0000_0000_0000_0000 ||
        (@addr & 0xffff_0000_0000 == 0xffff_0000_0000 && (
          @addr & 0xff000000 == 0x0a000000 ||  # ::ffff:10.0.0.0/8
          @addr & 0xfff00000 == 0xac100000 ||  # ::ffff::172.16.0.0/12
          @addr & 0xffff0000 == 0xc0a80000     # ::ffff::192.168.0.0/16
        ))
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  # Returns true if the ipaddr is a link-local address.  IPv4
  # addresses in 169.254.0.0/16 reserved by RFC 3927 and Link-Local
  # IPv6 Unicast Addresses in fe80::/10 reserved by RFC 4291 are
  # considered link-local.
  def link_local?
    case @family
    when Socket::AF_INET
      @addr & 0xffff0000 == 0xa9fe0000 # 169.254.0.0/16
    when Socket::AF_INET6
      @addr & 0xffc0_0000_0000_0000_0000_0000_0000_0000 == 0xfe80_0000_0000_0000_0000_0000_0000_0000
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  # Returns true if the ipaddr is an IPv4-mapped IPv6 address.
  def ipv4_mapped?
    return ipv6? && (@addr >> 32) == 0xffff
  end

  # Returns true if the ipaddr is an IPv4-compatible IPv6 address.
  def ipv4_compat?
    warn "IPAddr\##{__callee__} is obsolete", uplevel: 1 if $VERBOSE
    _ipv4_compat?
  end

  def _ipv4_compat?
    if !ipv6? || (@addr >> 32) != 0
      return false
    end
    a = (@addr & IN4MASK)
    return a != 0 && a != 1
  end

  private :_ipv4_compat?

  # Returns a new ipaddr built by converting the native IPv4 address
  # into an IPv4-mapped IPv6 address.
  def ipv4_mapped
    if !ipv4?
      raise InvalidAddressError, "not an IPv4 address: #{@addr}"
    end
    clone = self.clone.set(@addr | 0xffff00000000, Socket::AF_INET6)
    clone.instance_variable_set(:@mask_addr, @mask_addr | 0xffffffffffffffffffffffff00000000)
    clone
  end

  # Returns a new ipaddr built by converting the native IPv4 address
  # into an IPv4-compatible IPv6 address.
  def ipv4_compat
    warn "IPAddr\##{__callee__} is obsolete", uplevel: 1 if $VERBOSE
    if !ipv4?
      raise InvalidAddressError, "not an IPv4 address: #{@addr}"
    end
    return self.clone.set(@addr, Socket::AF_INET6)
  end

  # Returns a new ipaddr built by converting the IPv6 address into a
  # native IPv4 address.  If the IP address is not an IPv4-mapped or
  # IPv4-compatible IPv6 address, returns self.
  def native
    if !ipv4_mapped? && !_ipv4_compat?
      return self
    end
    return self.clone.set(@addr & IN4MASK, Socket::AF_INET)
  end

  # Returns a string for DNS reverse lookup.  It returns a string in
  # RFC3172 form for an IPv6 address.
  def reverse
    case @family
    when Socket::AF_INET
      return _reverse + ".in-addr.arpa"
    when Socket::AF_INET6
      return ip6_arpa
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  # Returns a string for DNS reverse lookup compatible with RFC3172.
  def ip6_arpa
    if !ipv6?
      raise InvalidAddressError, "not an IPv6 address: #{@addr}"
    end
    return _reverse + ".ip6.arpa"
  end

  # Returns a string for DNS reverse lookup compatible with RFC1886.
  def ip6_int
    if !ipv6?
      raise InvalidAddressError, "not an IPv6 address: #{@addr}"
    end
    return _reverse + ".ip6.int"
  end

  # Returns the successor to the ipaddr.
  def succ
    return self.clone.set(@addr + 1, @family)
  end

  # Compares the ipaddr with another.
  def <=>(other)
    other = coerce_other(other)
  rescue
    nil
  else
    @addr <=> other.to_i if other.family == @family
  end
  include Comparable

  # Checks equality used by Hash.
  def eql?(other)
    return self.class == other.class && self.hash == other.hash && self == other
  end

  # Returns a hash value used by Hash, Set, and Array classes
  def hash
    return ([@addr, @mask_addr, @zone_id].hash << 1) | (ipv4? ? 0 : 1)
  end

  # Creates a Range object for the network address.
  def to_range
    self.class.new(begin_addr, @family)..self.class.new(end_addr, @family)
  end

  # Returns the prefix length in bits for the ipaddr.
  def prefix
    case @family
    when Socket::AF_INET
      n = IN4MASK ^ @mask_addr
      i = 32
    when Socket::AF_INET6
      n = IN6MASK ^ @mask_addr
      i = 128
    else
      raise AddressFamilyError, "unsupported address family"
    end
    while n.positive?
      n >>= 1
      i -= 1
    end
    i
  end

  # Sets the prefix length in bits
  def prefix=(prefix)
    case prefix
    when Integer
      mask!(prefix)
    else
      raise InvalidPrefixError, "prefix must be an integer: #{@addr}"
    end
  end

  # Returns a string containing a human-readable representation of the
  # ipaddr. ("#<IPAddr: family:address/mask>")
  def inspect
    case @family
    when Socket::AF_INET
      af = "IPv4"
    when Socket::AF_INET6
      af = "IPv6"
      zone_id = @zone_id.to_s
    else
      raise AddressFamilyError, "unsupported address family"
    end
    return sprintf("#<%s: %s:%s%s/%s>", self.class.name,
                   af, _to_string(@addr), zone_id, _to_string(@mask_addr))
  end

  # Returns the netmask in string format e.g. 255.255.0.0
  def netmask
    _to_string(@mask_addr)
  end

  # Returns the IPv6 zone identifier, if present.
  # Raises InvalidAddressError if not an IPv6 address.
  def zone_id
    if @family == Socket::AF_INET6
      @zone_id
    else
      raise InvalidAddressError, "not an IPv6 address"
    end
  end

  # Returns the IPv6 zone identifier, if present.
  # Raises InvalidAddressError if not an IPv6 address.
  def zone_id=(zid)
    if @family == Socket::AF_INET6
      case zid
      when nil, /\A%(\w+)\z/
        @zone_id = zid
      else
        raise InvalidAddressError, "invalid zone identifier for address"
      end
    else
      raise InvalidAddressError, "not an IPv6 address"
    end
  end

  protected

  def begin_addr
    @addr & @mask_addr
  end

  def end_addr
    case @family
    when Socket::AF_INET
      @addr | (IN4MASK ^ @mask_addr)
    when Socket::AF_INET6
      @addr | (IN6MASK ^ @mask_addr)
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  # Set +@addr+, the internal stored ip address, to given +addr+. The
  # parameter +addr+ is validated using the first +family+ member,
  # which is +Socket::AF_INET+ or +Socket::AF_INET6+.
  def set(addr, *family)
    case family[0] ? family[0] : @family
    when Socket::AF_INET
      if addr < 0 || addr > IN4MASK
        raise InvalidAddressError, "invalid address: #{@addr}"
      end
    when Socket::AF_INET6
      if addr < 0 || addr > IN6MASK
        raise InvalidAddressError, "invalid address: #{@addr}"
      end
    else
      raise AddressFamilyError, "unsupported address family"
    end
    @addr = addr
    if family[0]
      @family = family[0]
      if @family == Socket::AF_INET
        @mask_addr &= IN4MASK
      end
    end
    return self
  end

  # Set current netmask to given mask.
  def mask!(mask)
    case mask
    when String
      case mask
      when /\A(0|[1-9]+\d*)\z/
        prefixlen = mask.to_i
      when /\A\d+\z/
        raise InvalidPrefixError, "leading zeros in prefix"
      else
        m = IPAddr.new(mask)
        if m.family != @family
          raise InvalidPrefixError, "address family is not same: #{@addr}"
        end
        @mask_addr = m.to_i
        n = @mask_addr ^ m.instance_variable_get(:@mask_addr)
        unless ((n + 1) & n).zero?
          raise InvalidPrefixError, "invalid mask #{mask}: #{@addr}"
        end
        @addr &= @mask_addr
        return self
      end
    else
      prefixlen = mask
    end
    case @family
    when Socket::AF_INET
      if prefixlen < 0 || prefixlen > 32
        raise InvalidPrefixError, "invalid length: #{@addr}"
      end
      masklen = 32 - prefixlen
      @mask_addr = ((IN4MASK >> masklen) << masklen)
    when Socket::AF_INET6
      if prefixlen < 0 || prefixlen > 128
        raise InvalidPrefixError, "invalid length: #{@addr}"
      end
      masklen = 128 - prefixlen
      @mask_addr = ((IN6MASK >> masklen) << masklen)
    else
      raise AddressFamilyError, "unsupported address family"
    end
    @addr = ((@addr >> masklen) << masklen)
    return self
  end

  private

  # Creates a new ipaddr object either from a human readable IP
  # address representation in string, or from a packed in_addr value
  # followed by an address family.
  #
  # In the former case, the following are the valid formats that will
  # be recognized: "address", "address/prefixlen" and "address/mask",
  # where IPv6 address may be enclosed in square brackets (`[' and
  # `]').  If a prefixlen or a mask is specified, it returns a masked
  # IP address.  Although the address family is determined
  # automatically from a specified string, you can specify one
  # explicitly by the optional second argument.
  #
  # Otherwise an IP address is generated from a packed in_addr value
  # and an address family.
  #
  # The IPAddr class defines many methods and operators, and some of
  # those, such as &, |, include? and ==, accept a string, or a packed
  # in_addr value instead of an IPAddr object.
  def initialize(addr = '::', family = Socket::AF_UNSPEC)
    @mask_addr = nil
    if !addr.kind_of?(String)
      case family
      when Socket::AF_INET, Socket::AF_INET6
        set(addr.to_i, family)
        @mask_addr = (family == Socket::AF_INET) ? IN4MASK : IN6MASK
        return
      when Socket::AF_UNSPEC
        raise AddressFamilyError, "address family must be specified"
      else
        raise AddressFamilyError, "unsupported address family: #{family}"
      end
    end
    prefix, prefixlen = addr.split('/', 2)
    if prefix =~ /\A\[(.*)\]\z/i
      prefix = $1
      family = Socket::AF_INET6
    end
    if prefix =~ /\A(.*)(%\w+)\z/
      prefix = $1
      zone_id = $2
      family = Socket::AF_INET6
    end
    # It seems AI_NUMERICHOST doesn't do the job.
    #Socket.getaddrinfo(left, nil, Socket::AF_INET6, Socket::SOCK_STREAM, nil,
    #                  Socket::AI_NUMERICHOST)
    @addr = @family = nil
    if family == Socket::AF_UNSPEC || family == Socket::AF_INET
      @addr = in_addr(prefix)
      if @addr
        @family = Socket::AF_INET
      end
    end
    if !@addr && (family == Socket::AF_UNSPEC || family == Socket::AF_INET6)
      @addr = in6_addr(prefix)
      @family = Socket::AF_INET6
    end
    @zone_id = zone_id
    if family != Socket::AF_UNSPEC && @family != family
      raise AddressFamilyError, "address family mismatch"
    end
    if prefixlen
      mask!(prefixlen)
    else
      @mask_addr = (@family == Socket::AF_INET) ? IN4MASK : IN6MASK
    end
  end

  def coerce_other(other)
    case other
    when IPAddr
      other
    when String
      self.class.new(other)
    else
      self.class.new(other, @family)
    end
  end

  def in_addr(addr)
    case addr
    when Array
      octets = addr
    else
      m = RE_IPV4ADDRLIKE.match(addr) or return nil
      octets = m.captures
    end
    octets.inject(0) { |i, s|
      (n = s.to_i) < 256 or raise InvalidAddressError, "invalid address: #{@addr}"
      s.match(/\A0./) and raise InvalidAddressError, "zero-filled number in IPv4 address is ambiguous: #{@addr}"
      i << 8 | n
    }
  end

  def in6_addr(left)
    case left
    when RE_IPV6ADDRLIKE_FULL
      if $2
        addr = in_addr($~[2,4])
        left = $1 + ':'
      else
        addr = 0
      end
      right = ''
    when RE_IPV6ADDRLIKE_COMPRESSED
      if $4
        left.count(':') <= 6 or raise InvalidAddressError, "invalid address: #{@addr}"
        addr = in_addr($~[4,4])
        left = $1
        right = $3 + '0:0'
      else
        left.count(':') <= ($1.empty? || $2.empty? ? 8 : 7) or
          raise InvalidAddressError, "invalid address: #{@addr}"
        left = $1
        right = $2
        addr = 0
      end
    else
      raise InvalidAddressError, "invalid address: #{@addr}"
    end
    l = left.split(':')
    r = right.split(':')
    rest = 8 - l.size - r.size
    if rest < 0
      return nil
    end
    (l + Array.new(rest, '0') + r).inject(0) { |i, s|
      i << 16 | s.hex
    } | addr
  end

  def addr_mask(addr)
    case @family
    when Socket::AF_INET
      return addr & IN4MASK
    when Socket::AF_INET6
      return addr & IN6MASK
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  def _reverse
    case @family
    when Socket::AF_INET
      return (0..3).map { |i|
        (@addr >> (8 * i)) & 0xff
      }.join('.')
    when Socket::AF_INET6
      return ("%.32x" % @addr).reverse!.gsub!(/.(?!$)/, '\&.')
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

  def _to_string(addr)
    case @family
    when Socket::AF_INET
      return (0..3).map { |i|
        (addr >> (24 - 8 * i)) & 0xff
      }.join('.')
    when Socket::AF_INET6
      return (("%.32x" % addr).gsub!(/.{4}(?!$)/, '\&:'))
    else
      raise AddressFamilyError, "unsupported address family"
    end
  end

end

unless Socket.const_defined? :AF_INET6
  class Socket < BasicSocket
    # IPv6 protocol family
    AF_INET6 = Object.new.freeze
  end

  class << IPSocket
    private

    def valid_v6?(addr)
      case addr
      when IPAddr::RE_IPV6ADDRLIKE_FULL
        if $2
          $~[2,4].all? {|i| i.to_i < 256 }
        else
          true
        end
      when IPAddr::RE_IPV6ADDRLIKE_COMPRESSED
        if $4
          addr.count(':') <= 6 && $~[4,4].all? {|i| i.to_i < 256}
        else
          addr.count(':') <= 7
        end
      else
        false
      end
    end

    alias getaddress_orig getaddress

    public

    # Returns a +String+ based representation of a valid DNS hostname,
    # IPv4 or IPv6 address.
    #
    #   IPSocket.getaddress 'localhost'         #=> "::1"
    #   IPSocket.getaddress 'broadcasthost'     #=> "255.255.255.255"
    #   IPSocket.getaddress 'www.ruby-lang.org' #=> "221.186.184.68"
    #   IPSocket.getaddress 'www.ccc.de'        #=> "2a00:1328:e102:ccc0::122"
    def getaddress(s)
      if valid_v6?(s)
        s
      else
        getaddress_orig(s)
      end
    end
  end
end
