# frozen_string_literal: true

require 'socket'
require 'timeout'
require 'io/wait'

begin
  require 'securerandom'
rescue LoadError
end

# Resolv is a thread-aware DNS resolver library written in Ruby.  Resolv can
# handle multiple DNS requests concurrently without blocking the entire Ruby
# interpreter.
#
# See also resolv-replace.rb to replace the libc resolver with Resolv.
#
# Resolv can look up various DNS resources using the DNS module directly.
#
# Examples:
#
#   p Resolv.getaddress "www.ruby-lang.org"
#   p Resolv.getname "210.251.121.214"
#
#   Resolv::DNS.open do |dns|
#     ress = dns.getresources "www.ruby-lang.org", Resolv::DNS::Resource::IN::A
#     p ress.map(&:address)
#     ress = dns.getresources "ruby-lang.org", Resolv::DNS::Resource::IN::MX
#     p ress.map { |r| [r.exchange.to_s, r.preference] }
#   end
#
#
# == Bugs
#
# * NIS is not supported.
# * /etc/nsswitch.conf is not supported.

class Resolv

  ##
  # Looks up the first IP address for +name+.

  def self.getaddress(name)
    DefaultResolver.getaddress(name)
  end

  ##
  # Looks up all IP address for +name+.

  def self.getaddresses(name)
    DefaultResolver.getaddresses(name)
  end

  ##
  # Iterates over all IP addresses for +name+.

  def self.each_address(name, &block)
    DefaultResolver.each_address(name, &block)
  end

  ##
  # Looks up the hostname of +address+.

  def self.getname(address)
    DefaultResolver.getname(address)
  end

  ##
  # Looks up all hostnames for +address+.

  def self.getnames(address)
    DefaultResolver.getnames(address)
  end

  ##
  # Iterates over all hostnames for +address+.

  def self.each_name(address, &proc)
    DefaultResolver.each_name(address, &proc)
  end

  ##
  # Creates a new Resolv using +resolvers+.

  def initialize(resolvers=[Hosts.new, DNS.new])
    @resolvers = resolvers
  end

  ##
  # Looks up the first IP address for +name+.

  def getaddress(name)
    each_address(name) {|address| return address}
    raise ResolvError.new("no address for #{name}")
  end

  ##
  # Looks up all IP address for +name+.

  def getaddresses(name)
    ret = []
    each_address(name) {|address| ret << address}
    return ret
  end

  ##
  # Iterates over all IP addresses for +name+.

  def each_address(name)
    if AddressRegex =~ name
      yield name
      return
    end
    yielded = false
    @resolvers.each {|r|
      r.each_address(name) {|address|
        yield address.to_s
        yielded = true
      }
      return if yielded
    }
  end

  ##
  # Looks up the hostname of +address+.

  def getname(address)
    each_name(address) {|name| return name}
    raise ResolvError.new("no name for #{address}")
  end

  ##
  # Looks up all hostnames for +address+.

  def getnames(address)
    ret = []
    each_name(address) {|name| ret << name}
    return ret
  end

  ##
  # Iterates over all hostnames for +address+.

  def each_name(address)
    yielded = false
    @resolvers.each {|r|
      r.each_name(address) {|name|
        yield name.to_s
        yielded = true
      }
      return if yielded
    }
  end

  ##
  # Indicates a failure to resolve a name or address.

  class ResolvError < StandardError; end

  ##
  # Indicates a timeout resolving a name or address.

  class ResolvTimeout < Timeout::Error; end

  ##
  # Resolv::Hosts is a hostname resolver that uses the system hosts file.

  class Hosts
    if /mswin|mingw|cygwin/ =~ RUBY_PLATFORM and
      begin
        require 'win32/resolv'
        DefaultFileName = Win32::Resolv.get_hosts_path || IO::NULL
      rescue LoadError
      end
    end
    DefaultFileName ||= '/etc/hosts'

    ##
    # Creates a new Resolv::Hosts, using +filename+ for its data source.

    def initialize(filename = DefaultFileName)
      @filename = filename
      @mutex = Thread::Mutex.new
      @initialized = nil
    end

    def lazy_initialize # :nodoc:
      @mutex.synchronize {
        unless @initialized
          @name2addr = {}
          @addr2name = {}
          File.open(@filename, 'rb') {|f|
            f.each {|line|
              line.sub!(/#.*/, '')
              addr, hostname, *aliases = line.split(/\s+/)
              next unless addr
              @addr2name[addr] = [] unless @addr2name.include? addr
              @addr2name[addr] << hostname
              @addr2name[addr] += aliases
              @name2addr[hostname] = [] unless @name2addr.include? hostname
              @name2addr[hostname] << addr
              aliases.each {|n|
                @name2addr[n] = [] unless @name2addr.include? n
                @name2addr[n] << addr
              }
            }
          }
          @name2addr.each {|name, arr| arr.reverse!}
          @initialized = true
        end
      }
      self
    end

    ##
    # Gets the IP address of +name+ from the hosts file.

    def getaddress(name)
      each_address(name) {|address| return address}
      raise ResolvError.new("#{@filename} has no name: #{name}")
    end

    ##
    # Gets all IP addresses for +name+ from the hosts file.

    def getaddresses(name)
      ret = []
      each_address(name) {|address| ret << address}
      return ret
    end

    ##
    # Iterates over all IP addresses for +name+ retrieved from the hosts file.

    def each_address(name, &proc)
      lazy_initialize
      @name2addr[name]&.each(&proc)
    end

    ##
    # Gets the hostname of +address+ from the hosts file.

    def getname(address)
      each_name(address) {|name| return name}
      raise ResolvError.new("#{@filename} has no address: #{address}")
    end

    ##
    # Gets all hostnames for +address+ from the hosts file.

    def getnames(address)
      ret = []
      each_name(address) {|name| ret << name}
      return ret
    end

    ##
    # Iterates over all hostnames for +address+ retrieved from the hosts file.

    def each_name(address, &proc)
      lazy_initialize
      @addr2name[address]&.each(&proc)
    end
  end

  ##
  # Resolv::DNS is a DNS stub resolver.
  #
  # Information taken from the following places:
  #
  # * STD0013
  # * RFC 1035
  # * ftp://ftp.isi.edu/in-notes/iana/assignments/dns-parameters
  # * etc.

  class DNS

    ##
    # Default DNS Port

    Port = 53

    ##
    # Default DNS UDP packet size

    UDPSize = 512

    ##
    # Creates a new DNS resolver.  See Resolv::DNS.new for argument details.
    #
    # Yields the created DNS resolver to the block, if given, otherwise
    # returns it.

    def self.open(*args)
      dns = new(*args)
      return dns unless block_given?
      begin
        yield dns
      ensure
        dns.close
      end
    end

    ##
    # Creates a new DNS resolver.
    #
    # +config_info+ can be:
    #
    # nil:: Uses /etc/resolv.conf.
    # String:: Path to a file using /etc/resolv.conf's format.
    # Hash:: Must contain :nameserver, :search and :ndots keys.
    # :nameserver_port can be used to specify port number of nameserver address.
    #
    # The value of :nameserver should be an address string or
    # an array of address strings.
    # - :nameserver => '8.8.8.8'
    # - :nameserver => ['8.8.8.8', '8.8.4.4']
    #
    # The value of :nameserver_port should be an array of
    # pair of nameserver address and port number.
    # - :nameserver_port => [['8.8.8.8', 53], ['8.8.4.4', 53]]
    #
    # Example:
    #
    #   Resolv::DNS.new(:nameserver => ['210.251.121.21'],
    #                   :search => ['ruby-lang.org'],
    #                   :ndots => 1)

    def initialize(config_info=nil)
      @mutex = Thread::Mutex.new
      @config = Config.new(config_info)
      @initialized = nil
    end

    # Sets the resolver timeouts.  This may be a single positive number
    # or an array of positive numbers representing timeouts in seconds.
    # If an array is specified, a DNS request will retry and wait for
    # each successive interval in the array until a successful response
    # is received.  Specifying +nil+ reverts to the default timeouts:
    # [ 5, second = 5 * 2 / nameserver_count, 2 * second, 4 * second ]
    #
    # Example:
    #
    #   dns.timeouts = 3
    #
    def timeouts=(values)
      @config.timeouts = values
    end

    def lazy_initialize # :nodoc:
      @mutex.synchronize {
        unless @initialized
          @config.lazy_initialize
          @initialized = true
        end
      }
      self
    end

    ##
    # Closes the DNS resolver.

    def close
      @mutex.synchronize {
        if @initialized
          @initialized = false
        end
      }
    end

    ##
    # Gets the IP address of +name+ from the DNS resolver.
    #
    # +name+ can be a Resolv::DNS::Name or a String.  Retrieved address will
    # be a Resolv::IPv4 or Resolv::IPv6

    def getaddress(name)
      each_address(name) {|address| return address}
      raise ResolvError.new("DNS result has no information for #{name}")
    end

    ##
    # Gets all IP addresses for +name+ from the DNS resolver.
    #
    # +name+ can be a Resolv::DNS::Name or a String.  Retrieved addresses will
    # be a Resolv::IPv4 or Resolv::IPv6

    def getaddresses(name)
      ret = []
      each_address(name) {|address| ret << address}
      return ret
    end

    ##
    # Iterates over all IP addresses for +name+ retrieved from the DNS
    # resolver.
    #
    # +name+ can be a Resolv::DNS::Name or a String.  Retrieved addresses will
    # be a Resolv::IPv4 or Resolv::IPv6

    def each_address(name)
      each_resource(name, Resource::IN::A) {|resource| yield resource.address}
      if use_ipv6?
        each_resource(name, Resource::IN::AAAA) {|resource| yield resource.address}
      end
    end

    def use_ipv6? # :nodoc:
      begin
        list = Socket.ip_address_list
      rescue NotImplementedError
        return true
      end
      list.any? {|a| a.ipv6? && !a.ipv6_loopback? && !a.ipv6_linklocal? }
    end
    private :use_ipv6?

    ##
    # Gets the hostname for +address+ from the DNS resolver.
    #
    # +address+ must be a Resolv::IPv4, Resolv::IPv6 or a String.  Retrieved
    # name will be a Resolv::DNS::Name.

    def getname(address)
      each_name(address) {|name| return name}
      raise ResolvError.new("DNS result has no information for #{address}")
    end

    ##
    # Gets all hostnames for +address+ from the DNS resolver.
    #
    # +address+ must be a Resolv::IPv4, Resolv::IPv6 or a String.  Retrieved
    # names will be Resolv::DNS::Name instances.

    def getnames(address)
      ret = []
      each_name(address) {|name| ret << name}
      return ret
    end

    ##
    # Iterates over all hostnames for +address+ retrieved from the DNS
    # resolver.
    #
    # +address+ must be a Resolv::IPv4, Resolv::IPv6 or a String.  Retrieved
    # names will be Resolv::DNS::Name instances.

    def each_name(address)
      case address
      when Name
        ptr = address
      when IPv4, IPv6
        ptr = address.to_name
      when IPv4::Regex
        ptr = IPv4.create(address).to_name
      when IPv6::Regex
        ptr = IPv6.create(address).to_name
      else
        raise ResolvError.new("cannot interpret as address: #{address}")
      end
      each_resource(ptr, Resource::IN::PTR) {|resource| yield resource.name}
    end

    ##
    # Look up the +typeclass+ DNS resource of +name+.
    #
    # +name+ must be a Resolv::DNS::Name or a String.
    #
    # +typeclass+ should be one of the following:
    #
    # * Resolv::DNS::Resource::IN::A
    # * Resolv::DNS::Resource::IN::AAAA
    # * Resolv::DNS::Resource::IN::ANY
    # * Resolv::DNS::Resource::IN::CNAME
    # * Resolv::DNS::Resource::IN::HINFO
    # * Resolv::DNS::Resource::IN::MINFO
    # * Resolv::DNS::Resource::IN::MX
    # * Resolv::DNS::Resource::IN::NS
    # * Resolv::DNS::Resource::IN::PTR
    # * Resolv::DNS::Resource::IN::SOA
    # * Resolv::DNS::Resource::IN::TXT
    # * Resolv::DNS::Resource::IN::WKS
    #
    # Returned resource is represented as a Resolv::DNS::Resource instance,
    # i.e. Resolv::DNS::Resource::IN::A.

    def getresource(name, typeclass)
      each_resource(name, typeclass) {|resource| return resource}
      raise ResolvError.new("DNS result has no information for #{name}")
    end

    ##
    # Looks up all +typeclass+ DNS resources for +name+.  See #getresource for
    # argument details.

    def getresources(name, typeclass)
      ret = []
      each_resource(name, typeclass) {|resource| ret << resource}
      return ret
    end

    ##
    # Iterates over all +typeclass+ DNS resources for +name+.  See
    # #getresource for argument details.

    def each_resource(name, typeclass, &proc)
      fetch_resource(name, typeclass) {|reply, reply_name|
        extract_resources(reply, reply_name, typeclass, &proc)
      }
    end

    def fetch_resource(name, typeclass)
      lazy_initialize
      begin
        requester = make_udp_requester
      rescue Errno::EACCES
        # fall back to TCP
      end
      senders = {}
      begin
        @config.resolv(name) {|candidate, tout, nameserver, port|
          requester ||= make_tcp_requester(nameserver, port)
          msg = Message.new
          msg.rd = 1
          msg.add_question(candidate, typeclass)
          unless sender = senders[[candidate, nameserver, port]]
            sender = requester.sender(msg, candidate, nameserver, port)
            next if !sender
            senders[[candidate, nameserver, port]] = sender
          end
          reply, reply_name = requester.request(sender, tout)
          case reply.rcode
          when RCode::NoError
            if reply.tc == 1 and not Requester::TCP === requester
              requester.close
              # Retry via TCP:
              requester = make_tcp_requester(nameserver, port)
              senders = {}
              # This will use TCP for all remaining candidates (assuming the
              # current candidate does not already respond successfully via
              # TCP).  This makes sense because we already know the full
              # response will not fit in an untruncated UDP packet.
              redo
            else
              yield(reply, reply_name)
            end
            return
          when RCode::NXDomain
            raise Config::NXDomain.new(reply_name.to_s)
          else
            raise Config::OtherResolvError.new(reply_name.to_s)
          end
        }
      ensure
        requester&.close
      end
    end

    def make_udp_requester # :nodoc:
      nameserver_port = @config.nameserver_port
      if nameserver_port.length == 1
        Requester::ConnectedUDP.new(*nameserver_port[0])
      else
        Requester::UnconnectedUDP.new(*nameserver_port)
      end
    end

    def make_tcp_requester(host, port) # :nodoc:
      return Requester::TCP.new(host, port)
    end

    def extract_resources(msg, name, typeclass) # :nodoc:
      if typeclass < Resource::ANY
        n0 = Name.create(name)
        msg.each_resource {|n, ttl, data|
          yield data if n0 == n
        }
      end
      yielded = false
      n0 = Name.create(name)
      msg.each_resource {|n, ttl, data|
        if n0 == n
          case data
          when typeclass
            yield data
            yielded = true
          when Resource::CNAME
            n0 = data.name
          end
        end
      }
      return if yielded
      msg.each_resource {|n, ttl, data|
        if n0 == n
          case data
          when typeclass
            yield data
          end
        end
      }
    end

    if defined? SecureRandom
      def self.random(arg) # :nodoc:
        begin
          SecureRandom.random_number(arg)
        rescue NotImplementedError
          rand(arg)
        end
      end
    else
      def self.random(arg) # :nodoc:
        rand(arg)
      end
    end

    RequestID = {} # :nodoc:
    RequestIDMutex = Thread::Mutex.new # :nodoc:

    def self.allocate_request_id(host, port) # :nodoc:
      id = nil
      RequestIDMutex.synchronize {
        h = (RequestID[[host, port]] ||= {})
        begin
          id = random(0x0000..0xffff)
        end while h[id]
        h[id] = true
      }
      id
    end

    def self.free_request_id(host, port, id) # :nodoc:
      RequestIDMutex.synchronize {
        key = [host, port]
        if h = RequestID[key]
          h.delete id
          if h.empty?
            RequestID.delete key
          end
        end
      }
    end

    def self.bind_random_port(udpsock, bind_host="0.0.0.0") # :nodoc:
      begin
        port = random(1024..65535)
        udpsock.bind(bind_host, port)
      rescue Errno::EADDRINUSE, # POSIX
             Errno::EACCES, # SunOS: See PRIV_SYS_NFS in privileges(5)
             Errno::EPERM # FreeBSD: security.mac.portacl.port_high is configurable.  See mac_portacl(4).
        retry
      end
    end

    class Requester # :nodoc:
      def initialize
        @senders = {}
        @socks = nil
      end

      def request(sender, tout)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        timelimit = start + tout
        begin
          sender.send
        rescue Errno::EHOSTUNREACH, # multi-homed IPv6 may generate this
               Errno::ENETUNREACH
          raise ResolvTimeout
        end
        while true
          before_select = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          timeout = timelimit - before_select
          if timeout <= 0
            raise ResolvTimeout
          end
          if @socks.size == 1
            select_result = @socks[0].wait_readable(timeout) ? [ @socks ] : nil
          else
            select_result = IO.select(@socks, nil, nil, timeout)
          end
          if !select_result
            after_select = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            next if after_select < timelimit
            raise ResolvTimeout
          end
          begin
            reply, from = recv_reply(select_result[0])
          rescue Errno::ECONNREFUSED, # GNU/Linux, FreeBSD
                 Errno::ECONNRESET # Windows
            # No name server running on the server?
            # Don't wait anymore.
            raise ResolvTimeout
          end
          begin
            msg = Message.decode(reply)
          rescue DecodeError
            next # broken DNS message ignored
          end
          if sender == sender_for(from, msg)
            break
          else
            # unexpected DNS message ignored
          end
        end
        return msg, sender.data
      end

      def sender_for(addr, msg)
        @senders[[addr,msg.id]]
      end

      def close
        socks = @socks
        @socks = nil
        socks&.each(&:close)
      end

      class Sender # :nodoc:
        def initialize(msg, data, sock)
          @msg = msg
          @data = data
          @sock = sock
        end
      end

      class UnconnectedUDP < Requester # :nodoc:
        def initialize(*nameserver_port)
          super()
          @nameserver_port = nameserver_port
          @initialized = false
          @mutex = Thread::Mutex.new
        end

        def lazy_initialize
          @mutex.synchronize {
            next if @initialized
            @initialized = true
            @socks_hash = {}
            @socks = []
            @nameserver_port.each {|host, port|
              if host.index(':')
                bind_host = "::"
                af = Socket::AF_INET6
              else
                bind_host = "0.0.0.0"
                af = Socket::AF_INET
              end
              next if @socks_hash[bind_host]
              begin
                sock = UDPSocket.new(af)
              rescue Errno::EAFNOSUPPORT
                next # The kernel doesn't support the address family.
              end
              @socks << sock
              @socks_hash[bind_host] = sock
              sock.do_not_reverse_lookup = true
              DNS.bind_random_port(sock, bind_host)
            }
          }
          self
        end

        def recv_reply(readable_socks)
          lazy_initialize
          reply, from = readable_socks[0].recvfrom(UDPSize)
          return reply, [from[3],from[1]]
        end

        def sender(msg, data, host, port=Port)
          host = Addrinfo.ip(host).ip_address
          lazy_initialize
          sock = @socks_hash[host.index(':') ? "::" : "0.0.0.0"]
          return nil if !sock
          service = [host, port]
          id = DNS.allocate_request_id(host, port)
          request = msg.encode
          request[0,2] = [id].pack('n')
          return @senders[[service, id]] =
            Sender.new(request, data, sock, host, port)
        end

        def close
          @mutex.synchronize {
            if @initialized
              super
              @senders.each_key {|service, id|
                DNS.free_request_id(service[0], service[1], id)
              }
              @initialized = false
            end
          }
        end

        class Sender < Requester::Sender # :nodoc:
          def initialize(msg, data, sock, host, port)
            super(msg, data, sock)
            @host = host
            @port = port
          end
          attr_reader :data

          def send
            raise "@sock is nil." if @sock.nil?
            @sock.send(@msg, 0, @host, @port)
          end
        end
      end

      class ConnectedUDP < Requester # :nodoc:
        def initialize(host, port=Port)
          super()
          @host = host
          @port = port
          @mutex = Thread::Mutex.new
          @initialized = false
        end

        def lazy_initialize
          @mutex.synchronize {
            next if @initialized
            @initialized = true
            is_ipv6 = @host.index(':')
            sock = UDPSocket.new(is_ipv6 ? Socket::AF_INET6 : Socket::AF_INET)
            @socks = [sock]
            sock.do_not_reverse_lookup = true
            DNS.bind_random_port(sock, is_ipv6 ? "::" : "0.0.0.0")
            sock.connect(@host, @port)
          }
          self
        end

        def recv_reply(readable_socks)
          lazy_initialize
          reply = readable_socks[0].recv(UDPSize)
          return reply, nil
        end

        def sender(msg, data, host=@host, port=@port)
          lazy_initialize
          unless host == @host && port == @port
            raise RequestError.new("host/port don't match: #{host}:#{port}")
          end
          id = DNS.allocate_request_id(@host, @port)
          request = msg.encode
          request[0,2] = [id].pack('n')
          return @senders[[nil,id]] = Sender.new(request, data, @socks[0])
        end

        def close
          @mutex.synchronize do
            if @initialized
              super
              @senders.each_key {|from, id|
                DNS.free_request_id(@host, @port, id)
              }
              @initialized = false
            end
          end
        end

        class Sender < Requester::Sender # :nodoc:
          def send
            raise "@sock is nil." if @sock.nil?
            @sock.send(@msg, 0)
          end
          attr_reader :data
        end
      end

      class MDNSOneShot < UnconnectedUDP # :nodoc:
        def sender(msg, data, host, port=Port)
          lazy_initialize
          id = DNS.allocate_request_id(host, port)
          request = msg.encode
          request[0,2] = [id].pack('n')
          sock = @socks_hash[host.index(':') ? "::" : "0.0.0.0"]
          return @senders[id] =
            UnconnectedUDP::Sender.new(request, data, sock, host, port)
        end

        def sender_for(addr, msg)
          lazy_initialize
          @senders[msg.id]
        end
      end

      class TCP < Requester # :nodoc:
        def initialize(host, port=Port)
          super()
          @host = host
          @port = port
          sock = TCPSocket.new(@host, @port)
          @socks = [sock]
          @senders = {}
        end

        def recv_reply(readable_socks)
          len = readable_socks[0].read(2).unpack('n')[0]
          reply = @socks[0].read(len)
          return reply, nil
        end

        def sender(msg, data, host=@host, port=@port)
          unless host == @host && port == @port
            raise RequestError.new("host/port don't match: #{host}:#{port}")
          end
          id = DNS.allocate_request_id(@host, @port)
          request = msg.encode
          request[0,2] = [request.length, id].pack('nn')
          return @senders[[nil,id]] = Sender.new(request, data, @socks[0])
        end

        class Sender < Requester::Sender # :nodoc:
          def send
            @sock.print(@msg)
            @sock.flush
          end
          attr_reader :data
        end

        def close
          super
          @senders.each_key {|from,id|
            DNS.free_request_id(@host, @port, id)
          }
        end
      end

      ##
      # Indicates a problem with the DNS request.

      class RequestError < StandardError
      end
    end

    class Config # :nodoc:
      def initialize(config_info=nil)
        @mutex = Thread::Mutex.new
        @config_info = config_info
        @initialized = nil
        @timeouts = nil
      end

      def timeouts=(values)
        if values
          values = Array(values)
          values.each do |t|
            Numeric === t or raise ArgumentError, "#{t.inspect} is not numeric"
            t > 0.0 or raise ArgumentError, "timeout=#{t} must be positive"
          end
          @timeouts = values
        else
          @timeouts = nil
        end
      end

      def Config.parse_resolv_conf(filename)
        nameserver = []
        search = nil
        ndots = 1
        File.open(filename, 'rb') {|f|
          f.each {|line|
            line.sub!(/[#;].*/, '')
            keyword, *args = line.split(/\s+/)
            next unless keyword
            case keyword
            when 'nameserver'
              nameserver += args
            when 'domain'
              next if args.empty?
              search = [args[0]]
            when 'search'
              next if args.empty?
              search = args
            when 'options'
              args.each {|arg|
                case arg
                when /\Andots:(\d+)\z/
                  ndots = $1.to_i
                end
              }
            end
          }
        }
        return { :nameserver => nameserver, :search => search, :ndots => ndots }
      end

      def Config.default_config_hash(filename="/etc/resolv.conf")
        if File.exist? filename
          config_hash = Config.parse_resolv_conf(filename)
        else
          if /mswin|cygwin|mingw|bccwin/ =~ RUBY_PLATFORM
            require 'win32/resolv'
            search, nameserver = Win32::Resolv.get_resolv_info
            config_hash = {}
            config_hash[:nameserver] = nameserver if nameserver
            config_hash[:search] = [search].flatten if search
          end
        end
        config_hash || {}
      end

      def lazy_initialize
        @mutex.synchronize {
          unless @initialized
            @nameserver_port = []
            @search = nil
            @ndots = 1
            case @config_info
            when nil
              config_hash = Config.default_config_hash
            when String
              config_hash = Config.parse_resolv_conf(@config_info)
            when Hash
              config_hash = @config_info.dup
              if String === config_hash[:nameserver]
                config_hash[:nameserver] = [config_hash[:nameserver]]
              end
              if String === config_hash[:search]
                config_hash[:search] = [config_hash[:search]]
              end
            else
              raise ArgumentError.new("invalid resolv configuration: #{@config_info.inspect}")
            end
            if config_hash.include? :nameserver
              @nameserver_port = config_hash[:nameserver].map {|ns| [ns, Port] }
            end
            if config_hash.include? :nameserver_port
              @nameserver_port = config_hash[:nameserver_port].map {|ns, port| [ns, (port || Port)] }
            end
            @search = config_hash[:search] if config_hash.include? :search
            @ndots = config_hash[:ndots] if config_hash.include? :ndots

            if @nameserver_port.empty?
              @nameserver_port << ['0.0.0.0', Port]
            end
            if @search
              @search = @search.map {|arg| Label.split(arg) }
            else
              hostname = Socket.gethostname
              if /\./ =~ hostname
                @search = [Label.split($')]
              else
                @search = [[]]
              end
            end

            if !@nameserver_port.kind_of?(Array) ||
               @nameserver_port.any? {|ns_port|
                  !(Array === ns_port) ||
                  ns_port.length != 2
                  !(String === ns_port[0]) ||
                  !(Integer === ns_port[1])
               }
              raise ArgumentError.new("invalid nameserver config: #{@nameserver_port.inspect}")
            end

            if !@search.kind_of?(Array) ||
               !@search.all? {|ls| ls.all? {|l| Label::Str === l } }
              raise ArgumentError.new("invalid search config: #{@search.inspect}")
            end

            if !@ndots.kind_of?(Integer)
              raise ArgumentError.new("invalid ndots config: #{@ndots.inspect}")
            end

            @initialized = true
          end
        }
        self
      end

      def single?
        lazy_initialize
        if @nameserver_port.length == 1
          return @nameserver_port[0]
        else
          return nil
        end
      end

      def nameserver_port
        @nameserver_port
      end

      def generate_candidates(name)
        candidates = nil
        name = Name.create(name)
        if name.absolute?
          candidates = [name]
        else
          if @ndots <= name.length - 1
            candidates = [Name.new(name.to_a)]
          else
            candidates = []
          end
          candidates.concat(@search.map {|domain| Name.new(name.to_a + domain)})
          fname = Name.create("#{name}.")
          if !candidates.include?(fname)
            candidates << fname
          end
        end
        return candidates
      end

      InitialTimeout = 5

      def generate_timeouts
        ts = [InitialTimeout]
        ts << ts[-1] * 2 / @nameserver_port.length
        ts << ts[-1] * 2
        ts << ts[-1] * 2
        return ts
      end

      def resolv(name)
        candidates = generate_candidates(name)
        timeouts = @timeouts || generate_timeouts
        begin
          candidates.each {|candidate|
            begin
              timeouts.each {|tout|
                @nameserver_port.each {|nameserver, port|
                  begin
                    yield candidate, tout, nameserver, port
                  rescue ResolvTimeout
                  end
                }
              }
              raise ResolvError.new("DNS resolv timeout: #{name}")
            rescue NXDomain
            end
          }
        rescue ResolvError
        end
      end

      ##
      # Indicates no such domain was found.

      class NXDomain < ResolvError
      end

      ##
      # Indicates some other unhandled resolver error was encountered.

      class OtherResolvError < ResolvError
      end
    end

    module OpCode # :nodoc:
      Query = 0
      IQuery = 1
      Status = 2
      Notify = 4
      Update = 5
    end

    module RCode # :nodoc:
      NoError = 0
      FormErr = 1
      ServFail = 2
      NXDomain = 3
      NotImp = 4
      Refused = 5
      YXDomain = 6
      YXRRSet = 7
      NXRRSet = 8
      NotAuth = 9
      NotZone = 10
      BADVERS = 16
      BADSIG = 16
      BADKEY = 17
      BADTIME = 18
      BADMODE = 19
      BADNAME = 20
      BADALG = 21
    end

    ##
    # Indicates that the DNS response was unable to be decoded.

    class DecodeError < StandardError
    end

    ##
    # Indicates that the DNS request was unable to be encoded.

    class EncodeError < StandardError
    end

    module Label # :nodoc:
      def self.split(arg)
        labels = []
        arg.scan(/[^\.]+/) {labels << Str.new($&)}
        return labels
      end

      class Str # :nodoc:
        def initialize(string)
          @string = string
          # case insensivity of DNS labels doesn't apply non-ASCII characters. [RFC 4343]
          # This assumes @string is given in ASCII compatible encoding.
          @downcase = string.b.downcase
        end
        attr_reader :string, :downcase

        def to_s
          return @string
        end

        def inspect
          return "#<#{self.class} #{self}>"
        end

        def ==(other)
          return self.class == other.class && @downcase == other.downcase
        end

        def eql?(other)
          return self == other
        end

        def hash
          return @downcase.hash
        end
      end
    end

    ##
    # A representation of a DNS name.

    class Name

      ##
      # Creates a new DNS name from +arg+.  +arg+ can be:
      #
      # Name:: returns +arg+.
      # String:: Creates a new Name.

      def self.create(arg)
        case arg
        when Name
          return arg
        when String
          return Name.new(Label.split(arg), /\.\z/ =~ arg ? true : false)
        else
          raise ArgumentError.new("cannot interpret as DNS name: #{arg.inspect}")
        end
      end

      def initialize(labels, absolute=true) # :nodoc:
        labels = labels.map {|label|
          case label
          when String then Label::Str.new(label)
          when Label::Str then label
          else
            raise ArgumentError, "unexpected label: #{label.inspect}"
          end
        }
        @labels = labels
        @absolute = absolute
      end

      def inspect # :nodoc:
        "#<#{self.class}: #{self}#{@absolute ? '.' : ''}>"
      end

      ##
      # True if this name is absolute.

      def absolute?
        return @absolute
      end

      def ==(other) # :nodoc:
        return false unless Name === other
        return false unless @absolute == other.absolute?
        return @labels == other.to_a
      end

      alias eql? == # :nodoc:

      ##
      # Returns true if +other+ is a subdomain.
      #
      # Example:
      #
      #   domain = Resolv::DNS::Name.create("y.z")
      #   p Resolv::DNS::Name.create("w.x.y.z").subdomain_of?(domain) #=> true
      #   p Resolv::DNS::Name.create("x.y.z").subdomain_of?(domain) #=> true
      #   p Resolv::DNS::Name.create("y.z").subdomain_of?(domain) #=> false
      #   p Resolv::DNS::Name.create("z").subdomain_of?(domain) #=> false
      #   p Resolv::DNS::Name.create("x.y.z.").subdomain_of?(domain) #=> false
      #   p Resolv::DNS::Name.create("w.z").subdomain_of?(domain) #=> false
      #

      def subdomain_of?(other)
        raise ArgumentError, "not a domain name: #{other.inspect}" unless Name === other
        return false if @absolute != other.absolute?
        other_len = other.length
        return false if @labels.length <= other_len
        return @labels[-other_len, other_len] == other.to_a
      end

      def hash # :nodoc:
        return @labels.hash ^ @absolute.hash
      end

      def to_a # :nodoc:
        return @labels
      end

      def length # :nodoc:
        return @labels.length
      end

      def [](i) # :nodoc:
        return @labels[i]
      end

      ##
      # returns the domain name as a string.
      #
      # The domain name doesn't have a trailing dot even if the name object is
      # absolute.
      #
      # Example:
      #
      #   p Resolv::DNS::Name.create("x.y.z.").to_s #=> "x.y.z"
      #   p Resolv::DNS::Name.create("x.y.z").to_s #=> "x.y.z"

      def to_s
        return @labels.join('.')
      end
    end

    class Message # :nodoc:
      @@identifier = -1

      def initialize(id = (@@identifier += 1) & 0xffff)
        @id = id
        @qr = 0
        @opcode = 0
        @aa = 0
        @tc = 0
        @rd = 0 # recursion desired
        @ra = 0 # recursion available
        @rcode = 0
        @question = []
        @answer = []
        @authority = []
        @additional = []
      end

      attr_accessor :id, :qr, :opcode, :aa, :tc, :rd, :ra, :rcode
      attr_reader :question, :answer, :authority, :additional

      def ==(other)
        return @id == other.id &&
               @qr == other.qr &&
               @opcode == other.opcode &&
               @aa == other.aa &&
               @tc == other.tc &&
               @rd == other.rd &&
               @ra == other.ra &&
               @rcode == other.rcode &&
               @question == other.question &&
               @answer == other.answer &&
               @authority == other.authority &&
               @additional == other.additional
      end

      def add_question(name, typeclass)
        @question << [Name.create(name), typeclass]
      end

      def each_question
        @question.each {|name, typeclass|
          yield name, typeclass
        }
      end

      def add_answer(name, ttl, data)
        @answer << [Name.create(name), ttl, data]
      end

      def each_answer
        @answer.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def add_authority(name, ttl, data)
        @authority << [Name.create(name), ttl, data]
      end

      def each_authority
        @authority.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def add_additional(name, ttl, data)
        @additional << [Name.create(name), ttl, data]
      end

      def each_additional
        @additional.each {|name, ttl, data|
          yield name, ttl, data
        }
      end

      def each_resource
        each_answer {|name, ttl, data| yield name, ttl, data}
        each_authority {|name, ttl, data| yield name, ttl, data}
        each_additional {|name, ttl, data| yield name, ttl, data}
      end

      def encode
        return MessageEncoder.new {|msg|
          msg.put_pack('nnnnnn',
            @id,
            (@qr & 1) << 15 |
            (@opcode & 15) << 11 |
            (@aa & 1) << 10 |
            (@tc & 1) << 9 |
            (@rd & 1) << 8 |
            (@ra & 1) << 7 |
            (@rcode & 15),
            @question.length,
            @answer.length,
            @authority.length,
            @additional.length)
          @question.each {|q|
            name, typeclass = q
            msg.put_name(name)
            msg.put_pack('nn', typeclass::TypeValue, typeclass::ClassValue)
          }
          [@answer, @authority, @additional].each {|rr|
            rr.each {|r|
              name, ttl, data = r
              msg.put_name(name)
              msg.put_pack('nnN', data.class::TypeValue, data.class::ClassValue, ttl)
              msg.put_length16 {data.encode_rdata(msg)}
            }
          }
        }.to_s
      end

      class MessageEncoder # :nodoc:
        def initialize
          @data = ''.dup
          @names = {}
          yield self
        end

        def to_s
          return @data
        end

        def put_bytes(d)
          @data << d
        end

        def put_pack(template, *d)
          @data << d.pack(template)
        end

        def put_length16
          length_index = @data.length
          @data << "\0\0"
          data_start = @data.length
          yield
          data_end = @data.length
          @data[length_index, 2] = [data_end - data_start].pack("n")
        end

        def put_string(d)
          self.put_pack("C", d.length)
          @data << d
        end

        def put_string_list(ds)
          ds.each {|d|
            self.put_string(d)
          }
        end

        def put_name(d)
          put_labels(d.to_a)
        end

        def put_labels(d)
          d.each_index {|i|
            domain = d[i..-1]
            if idx = @names[domain]
              self.put_pack("n", 0xc000 | idx)
              return
            else
              if @data.length < 0x4000
                @names[domain] = @data.length
              end
              self.put_label(d[i])
            end
          }
          @data << "\0"
        end

        def put_label(d)
          self.put_string(d.to_s)
        end
      end

      def Message.decode(m)
        o = Message.new(0)
        MessageDecoder.new(m) {|msg|
          id, flag, qdcount, ancount, nscount, arcount =
            msg.get_unpack('nnnnnn')
          o.id = id
          o.qr = (flag >> 15) & 1
          o.opcode = (flag >> 11) & 15
          o.aa = (flag >> 10) & 1
          o.tc = (flag >> 9) & 1
          o.rd = (flag >> 8) & 1
          o.ra = (flag >> 7) & 1
          o.rcode = flag & 15
          (1..qdcount).each {
            name, typeclass = msg.get_question
            o.add_question(name, typeclass)
          }
          (1..ancount).each {
            name, ttl, data = msg.get_rr
            o.add_answer(name, ttl, data)
          }
          (1..nscount).each {
            name, ttl, data = msg.get_rr
            o.add_authority(name, ttl, data)
          }
          (1..arcount).each {
            name, ttl, data = msg.get_rr
            o.add_additional(name, ttl, data)
          }
        }
        return o
      end

      class MessageDecoder # :nodoc:
        def initialize(data)
          @data = data
          @index = 0
          @limit = data.bytesize
          yield self
        end

        def inspect
          "\#<#{self.class}: #{@data.byteslice(0, @index).inspect} #{@data.byteslice(@index..-1).inspect}>"
        end

        def get_length16
          len, = self.get_unpack('n')
          save_limit = @limit
          @limit = @index + len
          d = yield(len)
          if @index < @limit
            raise DecodeError.new("junk exists")
          elsif @limit < @index
            raise DecodeError.new("limit exceeded")
          end
          @limit = save_limit
          return d
        end

        def get_bytes(len = @limit - @index)
          raise DecodeError.new("limit exceeded") if @limit < @index + len
          d = @data.byteslice(@index, len)
          @index += len
          return d
        end

        def get_unpack(template)
          len = 0
          template.each_byte {|byte|
            byte = "%c" % byte
            case byte
            when ?c, ?C
              len += 1
            when ?n
              len += 2
            when ?N
              len += 4
            else
              raise StandardError.new("unsupported template: '#{byte.chr}' in '#{template}'")
            end
          }
          raise DecodeError.new("limit exceeded") if @limit < @index + len
          arr = @data.unpack("@#{@index}#{template}")
          @index += len
          return arr
        end

        def get_string
          raise DecodeError.new("limit exceeded") if @limit <= @index
          len = @data.getbyte(@index)
          raise DecodeError.new("limit exceeded") if @limit < @index + 1 + len
          d = @data.byteslice(@index + 1, len)
          @index += 1 + len
          return d
        end

        def get_string_list
          strings = []
          while @index < @limit
            strings << self.get_string
          end
          strings
        end

        def get_name
          return Name.new(self.get_labels)
        end

        def get_labels
          prev_index = @index
          save_index = nil
          d = []
          while true
            raise DecodeError.new("limit exceeded") if @limit <= @index
            case @data.getbyte(@index)
            when 0
              @index += 1
              if save_index
                @index = save_index
              end
              return d
            when 192..255
              idx = self.get_unpack('n')[0] & 0x3fff
              if prev_index <= idx
                raise DecodeError.new("non-backward name pointer")
              end
              prev_index = idx
              if !save_index
                save_index = @index
              end
              @index = idx
            else
              d << self.get_label
            end
          end
        end

        def get_label
          return Label::Str.new(self.get_string)
        end

        def get_question
          name = self.get_name
          type, klass = self.get_unpack("nn")
          return name, Resource.get_class(type, klass)
        end

        def get_rr
          name = self.get_name
          type, klass, ttl = self.get_unpack('nnN')
          typeclass = Resource.get_class(type, klass)
          res = self.get_length16 do
            begin
              typeclass.decode_rdata self
            rescue => e
              raise DecodeError, e.message, e.backtrace
            end
          end
          res.instance_variable_set :@ttl, ttl
          return name, ttl, res
        end
      end
    end

    ##
    # A DNS query abstract class.

    class Query
      def encode_rdata(msg) # :nodoc:
        raise EncodeError.new("#{self.class} is query.")
      end

      def self.decode_rdata(msg) # :nodoc:
        raise DecodeError.new("#{self.class} is query.")
      end
    end

    ##
    # A DNS resource abstract class.

    class Resource < Query

      ##
      # Remaining Time To Live for this Resource.

      attr_reader :ttl

      ClassHash = {} # :nodoc:

      def encode_rdata(msg) # :nodoc:
        raise NotImplementedError.new
      end

      def self.decode_rdata(msg) # :nodoc:
        raise NotImplementedError.new
      end

      def ==(other) # :nodoc:
        return false unless self.class == other.class
        s_ivars = self.instance_variables
        s_ivars.sort!
        s_ivars.delete :@ttl
        o_ivars = other.instance_variables
        o_ivars.sort!
        o_ivars.delete :@ttl
        return s_ivars == o_ivars &&
          s_ivars.collect {|name| self.instance_variable_get name} ==
            o_ivars.collect {|name| other.instance_variable_get name}
      end

      def eql?(other) # :nodoc:
        return self == other
      end

      def hash # :nodoc:
        h = 0
        vars = self.instance_variables
        vars.delete :@ttl
        vars.each {|name|
          h ^= self.instance_variable_get(name).hash
        }
        return h
      end

      def self.get_class(type_value, class_value) # :nodoc:
        return ClassHash[[type_value, class_value]] ||
               Generic.create(type_value, class_value)
      end

      ##
      # A generic resource abstract class.

      class Generic < Resource

        ##
        # Creates a new generic resource.

        def initialize(data)
          @data = data
        end

        ##
        # Data for this generic resource.

        attr_reader :data

        def encode_rdata(msg) # :nodoc:
          msg.put_bytes(data)
        end

        def self.decode_rdata(msg) # :nodoc:
          return self.new(msg.get_bytes)
        end

        def self.create(type_value, class_value) # :nodoc:
          c = Class.new(Generic)
          c.const_set(:TypeValue, type_value)
          c.const_set(:ClassValue, class_value)
          Generic.const_set("Type#{type_value}_Class#{class_value}", c)
          ClassHash[[type_value, class_value]] = c
          return c
        end
      end

      ##
      # Domain Name resource abstract class.

      class DomainName < Resource

        ##
        # Creates a new DomainName from +name+.

        def initialize(name)
          @name = name
        end

        ##
        # The name of this DomainName.

        attr_reader :name

        def encode_rdata(msg) # :nodoc:
          msg.put_name(@name)
        end

        def self.decode_rdata(msg) # :nodoc:
          return self.new(msg.get_name)
        end
      end

      # Standard (class generic) RRs

      ClassValue = nil # :nodoc:

      ##
      # An authoritative name server.

      class NS < DomainName
        TypeValue = 2 # :nodoc:
      end

      ##
      # The canonical name for an alias.

      class CNAME < DomainName
        TypeValue = 5 # :nodoc:
      end

      ##
      # Start Of Authority resource.

      class SOA < Resource

        TypeValue = 6 # :nodoc:

        ##
        # Creates a new SOA record.  See the attr documentation for the
        # details of each argument.

        def initialize(mname, rname, serial, refresh, retry_, expire, minimum)
          @mname = mname
          @rname = rname
          @serial = serial
          @refresh = refresh
          @retry = retry_
          @expire = expire
          @minimum = minimum
        end

        ##
        # Name of the host where the master zone file for this zone resides.

        attr_reader :mname

        ##
        # The person responsible for this domain name.

        attr_reader :rname

        ##
        # The version number of the zone file.

        attr_reader :serial

        ##
        # How often, in seconds, a secondary name server is to check for
        # updates from the primary name server.

        attr_reader :refresh

        ##
        # How often, in seconds, a secondary name server is to retry after a
        # failure to check for a refresh.

        attr_reader :retry

        ##
        # Time in seconds that a secondary name server is to use the data
        # before refreshing from the primary name server.

        attr_reader :expire

        ##
        # The minimum number of seconds to be used for TTL values in RRs.

        attr_reader :minimum

        def encode_rdata(msg) # :nodoc:
          msg.put_name(@mname)
          msg.put_name(@rname)
          msg.put_pack('NNNNN', @serial, @refresh, @retry, @expire, @minimum)
        end

        def self.decode_rdata(msg) # :nodoc:
          mname = msg.get_name
          rname = msg.get_name
          serial, refresh, retry_, expire, minimum = msg.get_unpack('NNNNN')
          return self.new(
            mname, rname, serial, refresh, retry_, expire, minimum)
        end
      end

      ##
      # A Pointer to another DNS name.

      class PTR < DomainName
        TypeValue = 12 # :nodoc:
      end

      ##
      # Host Information resource.

      class HINFO < Resource

        TypeValue = 13 # :nodoc:

        ##
        # Creates a new HINFO running +os+ on +cpu+.

        def initialize(cpu, os)
          @cpu = cpu
          @os = os
        end

        ##
        # CPU architecture for this resource.

        attr_reader :cpu

        ##
        # Operating system for this resource.

        attr_reader :os

        def encode_rdata(msg) # :nodoc:
          msg.put_string(@cpu)
          msg.put_string(@os)
        end

        def self.decode_rdata(msg) # :nodoc:
          cpu = msg.get_string
          os = msg.get_string
          return self.new(cpu, os)
        end
      end

      ##
      # Mailing list or mailbox information.

      class MINFO < Resource

        TypeValue = 14 # :nodoc:

        def initialize(rmailbx, emailbx)
          @rmailbx = rmailbx
          @emailbx = emailbx
        end

        ##
        # Domain name responsible for this mail list or mailbox.

        attr_reader :rmailbx

        ##
        # Mailbox to use for error messages related to the mail list or mailbox.

        attr_reader :emailbx

        def encode_rdata(msg) # :nodoc:
          msg.put_name(@rmailbx)
          msg.put_name(@emailbx)
        end

        def self.decode_rdata(msg) # :nodoc:
          rmailbx = msg.get_string
          emailbx = msg.get_string
          return self.new(rmailbx, emailbx)
        end
      end

      ##
      # Mail Exchanger resource.

      class MX < Resource

        TypeValue= 15 # :nodoc:

        ##
        # Creates a new MX record with +preference+, accepting mail at
        # +exchange+.

        def initialize(preference, exchange)
          @preference = preference
          @exchange = exchange
        end

        ##
        # The preference for this MX.

        attr_reader :preference

        ##
        # The host of this MX.

        attr_reader :exchange

        def encode_rdata(msg) # :nodoc:
          msg.put_pack('n', @preference)
          msg.put_name(@exchange)
        end

        def self.decode_rdata(msg) # :nodoc:
          preference, = msg.get_unpack('n')
          exchange = msg.get_name
          return self.new(preference, exchange)
        end
      end

      ##
      # Unstructured text resource.

      class TXT < Resource

        TypeValue = 16 # :nodoc:

        def initialize(first_string, *rest_strings)
          @strings = [first_string, *rest_strings]
        end

        ##
        # Returns an Array of Strings for this TXT record.

        attr_reader :strings

        ##
        # Returns the concatenated string from +strings+.

        def data
          @strings.join("")
        end

        def encode_rdata(msg) # :nodoc:
          msg.put_string_list(@strings)
        end

        def self.decode_rdata(msg) # :nodoc:
          strings = msg.get_string_list
          return self.new(*strings)
        end
      end

      ##
      # Location resource

      class LOC < Resource

        TypeValue = 29 # :nodoc:

        def initialize(version, ssize, hprecision, vprecision, latitude, longitude, altitude)
          @version    = version
          @ssize      = Resolv::LOC::Size.create(ssize)
          @hprecision = Resolv::LOC::Size.create(hprecision)
          @vprecision = Resolv::LOC::Size.create(vprecision)
          @latitude   = Resolv::LOC::Coord.create(latitude)
          @longitude  = Resolv::LOC::Coord.create(longitude)
          @altitude   = Resolv::LOC::Alt.create(altitude)
        end

        ##
        # Returns the version value for this LOC record which should always be 00

        attr_reader :version

        ##
        # The spherical size of this LOC
        # in meters using scientific notation as 2 integers of XeY

        attr_reader :ssize

        ##
        # The horizontal precision using ssize type values
        # in meters using scientific notation as 2 integers of XeY
        # for precision use value/2 e.g. 2m = +/-1m

        attr_reader :hprecision

        ##
        # The vertical precision using ssize type values
        # in meters using scientific notation as 2 integers of XeY
        # for precision use value/2 e.g. 2m = +/-1m

        attr_reader :vprecision

        ##
        # The latitude for this LOC where 2**31 is the equator
        # in thousandths of an arc second as an unsigned 32bit integer

        attr_reader :latitude

        ##
        # The longitude for this LOC where 2**31 is the prime meridian
        # in thousandths of an arc second as an unsigned 32bit integer

        attr_reader :longitude

        ##
        # The altitude of the LOC above a reference sphere whose surface sits 100km below the WGS84 spheroid
        # in centimeters as an unsigned 32bit integer

        attr_reader :altitude


        def encode_rdata(msg) # :nodoc:
          msg.put_bytes(@version)
          msg.put_bytes(@ssize.scalar)
          msg.put_bytes(@hprecision.scalar)
          msg.put_bytes(@vprecision.scalar)
          msg.put_bytes(@latitude.coordinates)
          msg.put_bytes(@longitude.coordinates)
          msg.put_bytes(@altitude.altitude)
        end

        def self.decode_rdata(msg) # :nodoc:
          version    = msg.get_bytes(1)
          ssize      = msg.get_bytes(1)
          hprecision = msg.get_bytes(1)
          vprecision = msg.get_bytes(1)
          latitude   = msg.get_bytes(4)
          longitude  = msg.get_bytes(4)
          altitude   = msg.get_bytes(4)
          return self.new(
            version,
            Resolv::LOC::Size.new(ssize),
            Resolv::LOC::Size.new(hprecision),
            Resolv::LOC::Size.new(vprecision),
            Resolv::LOC::Coord.new(latitude,"lat"),
            Resolv::LOC::Coord.new(longitude,"lon"),
            Resolv::LOC::Alt.new(altitude)
          )
        end
      end

      ##
      # A Query type requesting any RR.

      class ANY < Query
        TypeValue = 255 # :nodoc:
      end

      ClassInsensitiveTypes = [ # :nodoc:
        NS, CNAME, SOA, PTR, HINFO, MINFO, MX, TXT, LOC, ANY
      ]

      ##
      # module IN contains ARPA Internet specific RRs.

      module IN

        ClassValue = 1 # :nodoc:

        ClassInsensitiveTypes.each {|s|
          c = Class.new(s)
          c.const_set(:TypeValue, s::TypeValue)
          c.const_set(:ClassValue, ClassValue)
          ClassHash[[s::TypeValue, ClassValue]] = c
          self.const_set(s.name.sub(/.*::/, ''), c)
        }

        ##
        # IPv4 Address resource

        class A < Resource
          TypeValue = 1
          ClassValue = IN::ClassValue
          ClassHash[[TypeValue, ClassValue]] = self # :nodoc:

          ##
          # Creates a new A for +address+.

          def initialize(address)
            @address = IPv4.create(address)
          end

          ##
          # The Resolv::IPv4 address for this A.

          attr_reader :address

          def encode_rdata(msg) # :nodoc:
            msg.put_bytes(@address.address)
          end

          def self.decode_rdata(msg) # :nodoc:
            return self.new(IPv4.new(msg.get_bytes(4)))
          end
        end

        ##
        # Well Known Service resource.

        class WKS < Resource
          TypeValue = 11
          ClassValue = IN::ClassValue
          ClassHash[[TypeValue, ClassValue]] = self # :nodoc:

          def initialize(address, protocol, bitmap)
            @address = IPv4.create(address)
            @protocol = protocol
            @bitmap = bitmap
          end

          ##
          # The host these services run on.

          attr_reader :address

          ##
          # IP protocol number for these services.

          attr_reader :protocol

          ##
          # A bit map of enabled services on this host.
          #
          # If protocol is 6 (TCP) then the 26th bit corresponds to the SMTP
          # service (port 25).  If this bit is set, then an SMTP server should
          # be listening on TCP port 25; if zero, SMTP service is not
          # supported.

          attr_reader :bitmap

          def encode_rdata(msg) # :nodoc:
            msg.put_bytes(@address.address)
            msg.put_pack("n", @protocol)
            msg.put_bytes(@bitmap)
          end

          def self.decode_rdata(msg) # :nodoc:
            address = IPv4.new(msg.get_bytes(4))
            protocol, = msg.get_unpack("n")
            bitmap = msg.get_bytes
            return self.new(address, protocol, bitmap)
          end
        end

        ##
        # An IPv6 address record.

        class AAAA < Resource
          TypeValue = 28
          ClassValue = IN::ClassValue
          ClassHash[[TypeValue, ClassValue]] = self # :nodoc:

          ##
          # Creates a new AAAA for +address+.

          def initialize(address)
            @address = IPv6.create(address)
          end

          ##
          # The Resolv::IPv6 address for this AAAA.

          attr_reader :address

          def encode_rdata(msg) # :nodoc:
            msg.put_bytes(@address.address)
          end

          def self.decode_rdata(msg) # :nodoc:
            return self.new(IPv6.new(msg.get_bytes(16)))
          end
        end

        ##
        # SRV resource record defined in RFC 2782
        #
        # These records identify the hostname and port that a service is
        # available at.

        class SRV < Resource
          TypeValue = 33
          ClassValue = IN::ClassValue
          ClassHash[[TypeValue, ClassValue]] = self # :nodoc:

          # Create a SRV resource record.
          #
          # See the documentation for #priority, #weight, #port and #target
          # for +priority+, +weight+, +port and +target+ respectively.

          def initialize(priority, weight, port, target)
            @priority = priority.to_int
            @weight = weight.to_int
            @port = port.to_int
            @target = Name.create(target)
          end

          # The priority of this target host.
          #
          # A client MUST attempt to contact the target host with the
          # lowest-numbered priority it can reach; target hosts with the same
          # priority SHOULD be tried in an order defined by the weight field.
          # The range is 0-65535.  Note that it is not widely implemented and
          # should be set to zero.

          attr_reader :priority

          # A server selection mechanism.
          #
          # The weight field specifies a relative weight for entries with the
          # same priority. Larger weights SHOULD be given a proportionately
          # higher probability of being selected. The range of this number is
          # 0-65535.  Domain administrators SHOULD use Weight 0 when there
          # isn't any server selection to do, to make the RR easier to read
          # for humans (less noisy). Note that it is not widely implemented
          # and should be set to zero.

          attr_reader :weight

          # The port on this target host of this service.
          #
          # The range is 0-65535.

          attr_reader :port

          # The domain name of the target host.
          #
          # A target of "." means that the service is decidedly not available
          # at this domain.

          attr_reader :target

          def encode_rdata(msg) # :nodoc:
            msg.put_pack("n", @priority)
            msg.put_pack("n", @weight)
            msg.put_pack("n", @port)
            msg.put_name(@target)
          end

          def self.decode_rdata(msg) # :nodoc:
            priority, = msg.get_unpack("n")
            weight,   = msg.get_unpack("n")
            port,     = msg.get_unpack("n")
            target    = msg.get_name
            return self.new(priority, weight, port, target)
          end
        end
      end
    end
  end

  ##
  # A Resolv::DNS IPv4 address.

  class IPv4

    ##
    # Regular expression IPv4 addresses must match.

    Regex256 = /0
               |1(?:[0-9][0-9]?)?
               |2(?:[0-4][0-9]?|5[0-5]?|[6-9])?
               |[3-9][0-9]?/x
    Regex = /\A(#{Regex256})\.(#{Regex256})\.(#{Regex256})\.(#{Regex256})\z/

    def self.create(arg)
      case arg
      when IPv4
        return arg
      when Regex
        if (0..255) === (a = $1.to_i) &&
           (0..255) === (b = $2.to_i) &&
           (0..255) === (c = $3.to_i) &&
           (0..255) === (d = $4.to_i)
          return self.new([a, b, c, d].pack("CCCC"))
        else
          raise ArgumentError.new("IPv4 address with invalid value: " + arg)
        end
      else
        raise ArgumentError.new("cannot interpret as IPv4 address: #{arg.inspect}")
      end
    end

    def initialize(address) # :nodoc:
      unless address.kind_of?(String)
        raise ArgumentError, 'IPv4 address must be a string'
      end
      unless address.length == 4
        raise ArgumentError, "IPv4 address expects 4 bytes but #{address.length} bytes"
      end
      @address = address
    end

    ##
    # A String representation of this IPv4 address.

    ##
    # The raw IPv4 address as a String.

    attr_reader :address

    def to_s # :nodoc:
      return sprintf("%d.%d.%d.%d", *@address.unpack("CCCC"))
    end

    def inspect # :nodoc:
      return "#<#{self.class} #{self}>"
    end

    ##
    # Turns this IPv4 address into a Resolv::DNS::Name.

    def to_name
      return DNS::Name.create(
        '%d.%d.%d.%d.in-addr.arpa.' % @address.unpack('CCCC').reverse)
    end

    def ==(other) # :nodoc:
      return @address == other.address
    end

    def eql?(other) # :nodoc:
      return self == other
    end

    def hash # :nodoc:
      return @address.hash
    end
  end

  ##
  # A Resolv::DNS IPv6 address.

  class IPv6

    ##
    # IPv6 address format a:b:c:d:e:f:g:h
    Regex_8Hex = /\A
      (?:[0-9A-Fa-f]{1,4}:){7}
         [0-9A-Fa-f]{1,4}
      \z/x

    ##
    # Compressed IPv6 address format a::b

    Regex_CompressedHex = /\A
      ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?) ::
      ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?)
      \z/x

    ##
    # IPv4 mapped IPv6 address format a:b:c:d:e:f:w.x.y.z

    Regex_6Hex4Dec = /\A
      ((?:[0-9A-Fa-f]{1,4}:){6,6})
      (\d+)\.(\d+)\.(\d+)\.(\d+)
      \z/x

    ##
    # Compressed IPv4 mapped IPv6 address format a::b:w.x.y.z

    Regex_CompressedHex4Dec = /\A
      ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?) ::
      ((?:[0-9A-Fa-f]{1,4}:)*)
      (\d+)\.(\d+)\.(\d+)\.(\d+)
      \z/x

    ##
    # IPv6 link local address format fe80:b:c:d:e:f:g:h%em1
    Regex_8HexLinkLocal = /\A
      [Ff][Ee]80
      (?::[0-9A-Fa-f]{1,4}){7}
      %[0-9A-Za-z]+
      \z/x

    ##
    # Compressed IPv6 link local address format fe80::b%em1

    Regex_CompressedHexLinkLocal = /\A
      [Ff][Ee]80:
      (?:
        ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?) ::
        ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?)
        |
        :((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?)
      )?
      :[0-9A-Fa-f]{1,4}%[0-9A-Za-z.]+
      \z/x

    ##
    # A composite IPv6 address Regexp.

    Regex = /
      (?:#{Regex_8Hex}) |
      (?:#{Regex_CompressedHex}) |
      (?:#{Regex_6Hex4Dec}) |
      (?:#{Regex_CompressedHex4Dec}) |
      (?:#{Regex_8HexLinkLocal}) |
      (?:#{Regex_CompressedHexLinkLocal})
      /x

    ##
    # Creates a new IPv6 address from +arg+ which may be:
    #
    # IPv6:: returns +arg+.
    # String:: +arg+ must match one of the IPv6::Regex* constants

    def self.create(arg)
      case arg
      when IPv6
        return arg
      when String
        address = ''.b
        if Regex_8Hex =~ arg
          arg.scan(/[0-9A-Fa-f]+/) {|hex| address << [hex.hex].pack('n')}
        elsif Regex_CompressedHex =~ arg
          prefix = $1
          suffix = $2
          a1 = ''.b
          a2 = ''.b
          prefix.scan(/[0-9A-Fa-f]+/) {|hex| a1 << [hex.hex].pack('n')}
          suffix.scan(/[0-9A-Fa-f]+/) {|hex| a2 << [hex.hex].pack('n')}
          omitlen = 16 - a1.length - a2.length
          address << a1 << "\0" * omitlen << a2
        elsif Regex_6Hex4Dec =~ arg
          prefix, a, b, c, d = $1, $2.to_i, $3.to_i, $4.to_i, $5.to_i
          if (0..255) === a && (0..255) === b && (0..255) === c && (0..255) === d
            prefix.scan(/[0-9A-Fa-f]+/) {|hex| address << [hex.hex].pack('n')}
            address << [a, b, c, d].pack('CCCC')
          else
            raise ArgumentError.new("not numeric IPv6 address: " + arg)
          end
        elsif Regex_CompressedHex4Dec =~ arg
          prefix, suffix, a, b, c, d = $1, $2, $3.to_i, $4.to_i, $5.to_i, $6.to_i
          if (0..255) === a && (0..255) === b && (0..255) === c && (0..255) === d
            a1 = ''.b
            a2 = ''.b
            prefix.scan(/[0-9A-Fa-f]+/) {|hex| a1 << [hex.hex].pack('n')}
            suffix.scan(/[0-9A-Fa-f]+/) {|hex| a2 << [hex.hex].pack('n')}
            omitlen = 12 - a1.length - a2.length
            address << a1 << "\0" * omitlen << a2 << [a, b, c, d].pack('CCCC')
          else
            raise ArgumentError.new("not numeric IPv6 address: " + arg)
          end
        else
          raise ArgumentError.new("not numeric IPv6 address: " + arg)
        end
        return IPv6.new(address)
      else
        raise ArgumentError.new("cannot interpret as IPv6 address: #{arg.inspect}")
      end
    end

    def initialize(address) # :nodoc:
      unless address.kind_of?(String) && address.length == 16
        raise ArgumentError.new('IPv6 address must be 16 bytes')
      end
      @address = address
    end

    ##
    # The raw IPv6 address as a String.

    attr_reader :address

    def to_s # :nodoc:
      address = sprintf("%x:%x:%x:%x:%x:%x:%x:%x", *@address.unpack("nnnnnnnn"))
      unless address.sub!(/(^|:)0(:0)+(:|$)/, '::')
        address.sub!(/(^|:)0(:|$)/, '::')
      end
      return address
    end

    def inspect # :nodoc:
      return "#<#{self.class} #{self}>"
    end

    ##
    # Turns this IPv6 address into a Resolv::DNS::Name.
    #--
    # ip6.arpa should be searched too. [RFC3152]

    def to_name
      return DNS::Name.new(
        @address.unpack("H32")[0].split(//).reverse + ['ip6', 'arpa'])
    end

    def ==(other) # :nodoc:
      return @address == other.address
    end

    def eql?(other) # :nodoc:
      return self == other
    end

    def hash # :nodoc:
      return @address.hash
    end
  end

  ##
  # Resolv::MDNS is a one-shot Multicast DNS (mDNS) resolver.  It blindly
  # makes queries to the mDNS addresses without understanding anything about
  # multicast ports.
  #
  # Information taken form the following places:
  #
  # * RFC 6762

  class MDNS < DNS

    ##
    # Default mDNS Port

    Port = 5353

    ##
    # Default IPv4 mDNS address

    AddressV4 = '224.0.0.251'

    ##
    # Default IPv6 mDNS address

    AddressV6 = 'ff02::fb'

    ##
    # Default mDNS addresses

    Addresses = [
      [AddressV4, Port],
      [AddressV6, Port],
    ]

    ##
    # Creates a new one-shot Multicast DNS (mDNS) resolver.
    #
    # +config_info+ can be:
    #
    # nil::
    #   Uses the default mDNS addresses
    #
    # Hash::
    #   Must contain :nameserver or :nameserver_port like
    #   Resolv::DNS#initialize.

    def initialize(config_info=nil)
      if config_info then
        super({ nameserver_port: Addresses }.merge(config_info))
      else
        super(nameserver_port: Addresses)
      end
    end

    ##
    # Iterates over all IP addresses for +name+ retrieved from the mDNS
    # resolver, provided name ends with "local".  If the name does not end in
    # "local" no records will be returned.
    #
    # +name+ can be a Resolv::DNS::Name or a String.  Retrieved addresses will
    # be a Resolv::IPv4 or Resolv::IPv6

    def each_address(name)
      name = Resolv::DNS::Name.create(name)

      return unless name[-1].to_s == 'local'

      super(name)
    end

    def make_udp_requester # :nodoc:
      nameserver_port = @config.nameserver_port
      Requester::MDNSOneShot.new(*nameserver_port)
    end

  end

  module LOC

    ##
    # A Resolv::LOC::Size

    class Size

      Regex = /^(\d+\.*\d*)[m]$/

      ##
      # Creates a new LOC::Size from +arg+ which may be:
      #
      # LOC::Size:: returns +arg+.
      # String:: +arg+ must match the LOC::Size::Regex constant

      def self.create(arg)
        case arg
        when Size
          return arg
        when String
          scalar = ''
          if Regex =~ arg
            scalar = [(($1.to_f*(1e2)).to_i.to_s[0].to_i*(2**4)+(($1.to_f*(1e2)).to_i.to_s.length-1))].pack("C")
          else
            raise ArgumentError.new("not a properly formed Size string: " + arg)
          end
          return Size.new(scalar)
        else
          raise ArgumentError.new("cannot interpret as Size: #{arg.inspect}")
        end
      end

      def initialize(scalar)
        @scalar = scalar
      end

      ##
      # The raw size

      attr_reader :scalar

      def to_s # :nodoc:
        s = @scalar.unpack("H2").join.to_s
        return ((s[0].to_i)*(10**(s[1].to_i-2))).to_s << "m"
      end

      def inspect # :nodoc:
        return "#<#{self.class} #{self}>"
      end

      def ==(other) # :nodoc:
        return @scalar == other.scalar
      end

      def eql?(other) # :nodoc:
        return self == other
      end

      def hash # :nodoc:
        return @scalar.hash
      end

    end

    ##
    # A Resolv::LOC::Coord

    class Coord

      Regex = /^(\d+)\s(\d+)\s(\d+\.\d+)\s([NESW])$/

      ##
      # Creates a new LOC::Coord from +arg+ which may be:
      #
      # LOC::Coord:: returns +arg+.
      # String:: +arg+ must match the LOC::Coord::Regex constant

      def self.create(arg)
        case arg
        when Coord
          return arg
        when String
          coordinates = ''
          if Regex =~ arg && $1.to_f < 180
            m = $~
            hemi = (m[4][/[NE]/]) || (m[4][/[SW]/]) ? 1 : -1
            coordinates = [ ((m[1].to_i*(36e5)) + (m[2].to_i*(6e4)) +
                             (m[3].to_f*(1e3))) * hemi+(2**31) ].pack("N")
            orientation = m[4][/[NS]/] ? 'lat' : 'lon'
          else
            raise ArgumentError.new("not a properly formed Coord string: " + arg)
          end
          return Coord.new(coordinates,orientation)
        else
          raise ArgumentError.new("cannot interpret as Coord: #{arg.inspect}")
        end
      end

      def initialize(coordinates,orientation)
        unless coordinates.kind_of?(String)
          raise ArgumentError.new("Coord must be a 32bit unsigned integer in hex format: #{coordinates.inspect}")
        end
        unless orientation.kind_of?(String) && orientation[/^lon$|^lat$/]
          raise ArgumentError.new('Coord expects orientation to be a String argument of "lat" or "lon"')
        end
        @coordinates = coordinates
        @orientation = orientation
      end

      ##
      # The raw coordinates

      attr_reader :coordinates

      ## The orientation of the hemisphere as 'lat' or 'lon'

      attr_reader :orientation

      def to_s # :nodoc:
          c = @coordinates.unpack("N").join.to_i
          val      = (c - (2**31)).abs
          fracsecs = (val % 1e3).to_i.to_s
          val      = val / 1e3
          secs     = (val % 60).to_i.to_s
          val      = val / 60
          mins     = (val % 60).to_i.to_s
          degs     = (val / 60).to_i.to_s
          posi = (c >= 2**31)
          case posi
          when true
            hemi = @orientation[/^lat$/] ? "N" : "E"
          else
            hemi = @orientation[/^lon$/] ? "W" : "S"
          end
          return degs << " " << mins << " " << secs << "." << fracsecs << " " << hemi
      end

      def inspect # :nodoc:
        return "#<#{self.class} #{self}>"
      end

      def ==(other) # :nodoc:
        return @coordinates == other.coordinates
      end

      def eql?(other) # :nodoc:
        return self == other
      end

      def hash # :nodoc:
        return @coordinates.hash
      end

    end

    ##
    # A Resolv::LOC::Alt

    class Alt

      Regex = /^([+-]*\d+\.*\d*)[m]$/

      ##
      # Creates a new LOC::Alt from +arg+ which may be:
      #
      # LOC::Alt:: returns +arg+.
      # String:: +arg+ must match the LOC::Alt::Regex constant

      def self.create(arg)
        case arg
        when Alt
          return arg
        when String
          altitude = ''
          if Regex =~ arg
            altitude = [($1.to_f*(1e2))+(1e7)].pack("N")
          else
            raise ArgumentError.new("not a properly formed Alt string: " + arg)
          end
          return Alt.new(altitude)
        else
          raise ArgumentError.new("cannot interpret as Alt: #{arg.inspect}")
        end
      end

      def initialize(altitude)
        @altitude = altitude
      end

      ##
      # The raw altitude

      attr_reader :altitude

      def to_s # :nodoc:
        a = @altitude.unpack("N").join.to_i
        return ((a.to_f/1e2)-1e5).to_s + "m"
      end

      def inspect # :nodoc:
        return "#<#{self.class} #{self}>"
      end

      def ==(other) # :nodoc:
        return @altitude == other.altitude
      end

      def eql?(other) # :nodoc:
        return self == other
      end

      def hash # :nodoc:
        return @altitude.hash
      end

    end

  end

  ##
  # Default resolver to use for Resolv class methods.

  DefaultResolver = self.new

  ##
  # Replaces the resolvers in the default resolver with +new_resolvers+.  This
  # allows resolvers to be changed for resolv-replace.

  def DefaultResolver.replace_resolvers new_resolvers
    @resolvers = new_resolvers
  end

  ##
  # Address Regexp to use for matching IP addresses.

  AddressRegex = /(?:#{IPv4::Regex})|(?:#{IPv6::Regex})/

end

