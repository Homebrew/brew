# frozen_string_literal: true

# = uri/generic.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License:: You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

require_relative 'common'
autoload :IPSocket, 'socket'
autoload :IPAddr, 'ipaddr'

module URI

  #
  # Base class for all URI classes.
  # Implements generic URI syntax as per RFC 2396.
  #
  class Generic
    include URI

    #
    # A Default port of nil for URI::Generic.
    #
    DEFAULT_PORT = nil

    #
    # Returns default port.
    #
    def self.default_port
      self::DEFAULT_PORT
    end

    #
    # Returns default port.
    #
    def default_port
      self.class.default_port
    end

    #
    # An Array of the available components for URI::Generic.
    #
    COMPONENT = [
      :scheme,
      :userinfo, :host, :port, :registry,
      :path, :opaque,
      :query,
      :fragment
    ].freeze

    #
    # Components of the URI in the order.
    #
    def self.component
      self::COMPONENT
    end

    USE_REGISTRY = false # :nodoc:

    def self.use_registry # :nodoc:
      self::USE_REGISTRY
    end

    #
    # == Synopsis
    #
    # See ::new.
    #
    # == Description
    #
    # At first, tries to create a new URI::Generic instance using
    # URI::Generic::build. But, if exception URI::InvalidComponentError is raised,
    # then it does URI::Escape.escape all URI components and tries again.
    #
    def self.build2(args)
      begin
        return self.build(args)
      rescue InvalidComponentError
        if args.kind_of?(Array)
          return self.build(args.collect{|x|
            if x.is_a?(String)
              DEFAULT_PARSER.escape(x)
            else
              x
            end
          })
        elsif args.kind_of?(Hash)
          tmp = {}
          args.each do |key, value|
            tmp[key] = if value
                DEFAULT_PARSER.escape(value)
              else
                value
              end
          end
          return self.build(tmp)
        end
      end
    end

    #
    # == Synopsis
    #
    # See ::new.
    #
    # == Description
    #
    # Creates a new URI::Generic instance from components of URI::Generic
    # with check.  Components are: scheme, userinfo, host, port, registry, path,
    # opaque, query, and fragment. You can provide arguments either by an Array or a Hash.
    # See ::new for hash keys to use or for order of array items.
    #
    def self.build(args)
      if args.kind_of?(Array) &&
          args.size == ::URI::Generic::COMPONENT.size
        tmp = args.dup
      elsif args.kind_of?(Hash)
        tmp = ::URI::Generic::COMPONENT.collect do |c|
          if args.include?(c)
            args[c]
          else
            nil
          end
        end
      else
        component = self.class.component rescue ::URI::Generic::COMPONENT
        raise ArgumentError,
        "expected Array of or Hash of components of #{self.class} (#{component.join(', ')})"
      end

      tmp << nil
      tmp << true
      return self.new(*tmp)
    end

    #
    # == Args
    #
    # +scheme+::
    #   Protocol scheme, i.e. 'http','ftp','mailto' and so on.
    # +userinfo+::
    #   User name and password, i.e. 'sdmitry:bla'.
    # +host+::
    #   Server host name.
    # +port+::
    #   Server port.
    # +registry+::
    #   Registry of naming authorities.
    # +path+::
    #   Path on server.
    # +opaque+::
    #   Opaque part.
    # +query+::
    #   Query data.
    # +fragment+::
    #   Part of the URI after '#' character.
    # +parser+::
    #   Parser for internal use [URI::DEFAULT_PARSER by default].
    # +arg_check+::
    #   Check arguments [false by default].
    #
    # == Description
    #
    # Creates a new URI::Generic instance from ``generic'' components without check.
    #
    def initialize(scheme,
                   userinfo, host, port, registry,
                   path, opaque,
                   query,
                   fragment,
                   parser = DEFAULT_PARSER,
                   arg_check = false)
      @scheme = nil
      @user = nil
      @password = nil
      @host = nil
      @port = nil
      @path = nil
      @query = nil
      @opaque = nil
      @fragment = nil
      @parser = parser == DEFAULT_PARSER ? nil : parser

      if arg_check
        self.scheme = scheme
        self.userinfo = userinfo
        self.hostname = host
        self.port = port
        self.path = path
        self.query = query
        self.opaque = opaque
        self.fragment = fragment
      else
        self.set_scheme(scheme)
        self.set_userinfo(userinfo)
        self.set_host(host)
        self.set_port(port)
        self.set_path(path)
        self.query = query
        self.set_opaque(opaque)
        self.fragment=(fragment)
      end
      if registry
        raise InvalidURIError,
          "the scheme #{@scheme} does not accept registry part: #{registry} (or bad hostname?)"
      end

      @scheme&.freeze
      self.set_path('') if !@path && !@opaque # (see RFC2396 Section 5.2)
      self.set_port(self.default_port) if self.default_port && !@port
    end

    #
    # Returns the scheme component of the URI.
    #
    #   URI("http://foo/bar/baz").scheme #=> "http"
    #
    attr_reader :scheme

    # Returns the host component of the URI.
    #
    #   URI("http://foo/bar/baz").host #=> "foo"
    #
    # It returns nil if no host component exists.
    #
    #   URI("mailto:foo@example.org").host #=> nil
    #
    # The component does not contain the port number.
    #
    #   URI("http://foo:8080/bar/baz").host #=> "foo"
    #
    # Since IPv6 addresses are wrapped with brackets in URIs,
    # this method returns IPv6 addresses wrapped with brackets.
    # This form is not appropriate to pass to socket methods such as TCPSocket.open.
    # If unwrapped host names are required, use the #hostname method.
    #
    #   URI("http://[::1]/bar/baz").host     #=> "[::1]"
    #   URI("http://[::1]/bar/baz").hostname #=> "::1"
    #
    attr_reader :host

    # Returns the port component of the URI.
    #
    #   URI("http://foo/bar/baz").port      #=> 80
    #   URI("http://foo:8080/bar/baz").port #=> 8080
    #
    attr_reader :port

    def registry # :nodoc:
      nil
    end

    # Returns the path component of the URI.
    #
    #   URI("http://foo/bar/baz").path #=> "/bar/baz"
    #
    attr_reader :path

    # Returns the query component of the URI.
    #
    #   URI("http://foo/bar/baz?search=FooBar").query #=> "search=FooBar"
    #
    attr_reader :query

    # Returns the opaque part of the URI.
    #
    #   URI("mailto:foo@example.org").opaque #=> "foo@example.org"
    #   URI("http://foo/bar/baz").opaque     #=> nil
    #
    # The portion of the path that does not make use of the slash '/'.
    # The path typically refers to an absolute path or an opaque part.
    # (See RFC2396 Section 3 and 5.2.)
    #
    attr_reader :opaque

    # Returns the fragment component of the URI.
    #
    #   URI("http://foo/bar/baz?search=FooBar#ponies").fragment #=> "ponies"
    #
    attr_reader :fragment

    # Returns the parser to be used.
    #
    # Unless a URI::Parser is defined, DEFAULT_PARSER is used.
    #
    def parser
      if !defined?(@parser) || !@parser
        DEFAULT_PARSER
      else
        @parser || DEFAULT_PARSER
      end
    end

    # Replaces self by other URI object.
    #
    def replace!(oth)
      if self.class != oth.class
        raise ArgumentError, "expected #{self.class} object"
      end

      component.each do |c|
        self.__send__("#{c}=", oth.__send__(c))
      end
    end
    private :replace!

    #
    # Components of the URI in the order.
    #
    def component
      self.class.component
    end

    #
    # Checks the scheme +v+ component against the URI::Parser Regexp for :SCHEME.
    #
    def check_scheme(v)
      if v && parser.regexp[:SCHEME] !~ v
        raise InvalidComponentError,
          "bad component(expected scheme component): #{v}"
      end

      return true
    end
    private :check_scheme

    # Protected setter for the scheme component +v+.
    #
    # See also URI::Generic.scheme=.
    #
    def set_scheme(v)
      @scheme = v&.downcase
    end
    protected :set_scheme

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the scheme component +v+
    # (with validation).
    #
    # See also URI::Generic.check_scheme.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com")
    #   uri.scheme = "https"
    #   uri.to_s  #=> "https://my.example.com"
    #
    def scheme=(v)
      check_scheme(v)
      set_scheme(v)
      v
    end

    #
    # Checks the +user+ and +password+.
    #
    # If +password+ is not provided, then +user+ is
    # split, using URI::Generic.split_userinfo, to
    # pull +user+ and +password.
    #
    # See also URI::Generic.check_user, URI::Generic.check_password.
    #
    def check_userinfo(user, password = nil)
      if !password
        user, password = split_userinfo(user)
      end
      check_user(user)
      check_password(password, user)

      return true
    end
    private :check_userinfo

    #
    # Checks the user +v+ component for RFC2396 compliance
    # and against the URI::Parser Regexp for :USERINFO.
    #
    # Can not have a registry or opaque component defined,
    # with a user component defined.
    #
    def check_user(v)
      if @opaque
        raise InvalidURIError,
          "can not set user with opaque"
      end

      return v unless v

      if parser.regexp[:USERINFO] !~ v
        raise InvalidComponentError,
          "bad component(expected userinfo component or user component): #{v}"
      end

      return true
    end
    private :check_user

    #
    # Checks the password +v+ component for RFC2396 compliance
    # and against the URI::Parser Regexp for :USERINFO.
    #
    # Can not have a registry or opaque component defined,
    # with a user component defined.
    #
    def check_password(v, user = @user)
      if @opaque
        raise InvalidURIError,
          "can not set password with opaque"
      end
      return v unless v

      if !user
        raise InvalidURIError,
          "password component depends user component"
      end

      if parser.regexp[:USERINFO] !~ v
        raise InvalidComponentError,
          "bad password component"
      end

      return true
    end
    private :check_password

    #
    # Sets userinfo, argument is string like 'name:pass'.
    #
    def userinfo=(userinfo)
      if userinfo.nil?
        return nil
      end
      check_userinfo(*userinfo)
      set_userinfo(*userinfo)
      # returns userinfo
    end

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the +user+ component
    # (with validation).
    #
    # See also URI::Generic.check_user.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://john:S3nsit1ve@my.example.com")
    #   uri.user = "sam"
    #   uri.to_s  #=> "http://sam:V3ry_S3nsit1ve@my.example.com"
    #
    def user=(user)
      check_user(user)
      set_user(user)
      # returns user
    end

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the +password+ component
    # (with validation).
    #
    # See also URI::Generic.check_password.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://john:S3nsit1ve@my.example.com")
    #   uri.password = "V3ry_S3nsit1ve"
    #   uri.to_s  #=> "http://john:V3ry_S3nsit1ve@my.example.com"
    #
    def password=(password)
      check_password(password)
      set_password(password)
      # returns password
    end

    # Protected setter for the +user+ component, and +password+ if available
    # (with validation).
    #
    # See also URI::Generic.userinfo=.
    #
    def set_userinfo(user, password = nil)
      unless password
        user, password = split_userinfo(user)
      end
      @user     = user
      @password = password if password

      [@user, @password]
    end
    protected :set_userinfo

    # Protected setter for the user component +v+.
    #
    # See also URI::Generic.user=.
    #
    def set_user(v)
      set_userinfo(v, @password)
      v
    end
    protected :set_user

    # Protected setter for the password component +v+.
    #
    # See also URI::Generic.password=.
    #
    def set_password(v)
      @password = v
      # returns v
    end
    protected :set_password

    # Returns the userinfo +ui+ as <code>[user, password]</code>
    # if properly formatted as 'user:password'.
    def split_userinfo(ui)
      return nil, nil unless ui
      user, password = ui.split(':', 2)

      return user, password
    end
    private :split_userinfo

    # Escapes 'user:password' +v+ based on RFC 1738 section 3.1.
    def escape_userpass(v)
      parser.escape(v, /[@:\/]/o) # RFC 1738 section 3.1 #/
    end
    private :escape_userpass

    # Returns the userinfo, either as 'user' or 'user:password'.
    def userinfo
      if @user.nil?
        nil
      elsif @password.nil?
        @user
      else
        @user + ':' + @password
      end
    end

    # Returns the user component (without URI decoding).
    def user
      @user
    end

    # Returns the password component (without URI decoding).
    def password
      @password
    end

    # Returns the user component after URI decoding.
    def decoded_user
      URI.decode_uri_component(@user) if @user
    end

    # Returns the password component after URI decoding.
    def decoded_password
      URI.decode_uri_component(@password) if @password
    end

    #
    # Checks the host +v+ component for RFC2396 compliance
    # and against the URI::Parser Regexp for :HOST.
    #
    # Can not have a registry or opaque component defined,
    # with a host component defined.
    #
    def check_host(v)
      return v unless v

      if @opaque
        raise InvalidURIError,
          "can not set host with registry or opaque"
      elsif parser.regexp[:HOST] !~ v
        raise InvalidComponentError,
          "bad component(expected host component): #{v}"
      end

      return true
    end
    private :check_host

    # Protected setter for the host component +v+.
    #
    # See also URI::Generic.host=.
    #
    def set_host(v)
      @host = v
    end
    protected :set_host

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the host component +v+
    # (with validation).
    #
    # See also URI::Generic.check_host.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com")
    #   uri.host = "foo.com"
    #   uri.to_s  #=> "http://foo.com"
    #
    def host=(v)
      check_host(v)
      set_host(v)
      v
    end

    # Extract the host part of the URI and unwrap brackets for IPv6 addresses.
    #
    # This method is the same as URI::Generic#host except
    # brackets for IPv6 (and future IP) addresses are removed.
    #
    #   uri = URI("http://[::1]/bar")
    #   uri.hostname      #=> "::1"
    #   uri.host          #=> "[::1]"
    #
    def hostname
      v = self.host
      v&.start_with?('[') && v.end_with?(']') ? v[1..-2] : v
    end

    # Sets the host part of the URI as the argument with brackets for IPv6 addresses.
    #
    # This method is the same as URI::Generic#host= except
    # the argument can be a bare IPv6 address.
    #
    #   uri = URI("http://foo/bar")
    #   uri.hostname = "::1"
    #   uri.to_s  #=> "http://[::1]/bar"
    #
    # If the argument seems to be an IPv6 address,
    # it is wrapped with brackets.
    #
    def hostname=(v)
      v = "[#{v}]" if !(v&.start_with?('[') && v&.end_with?(']')) && v&.index(':')
      self.host = v
    end

    #
    # Checks the port +v+ component for RFC2396 compliance
    # and against the URI::Parser Regexp for :PORT.
    #
    # Can not have a registry or opaque component defined,
    # with a port component defined.
    #
    def check_port(v)
      return v unless v

      if @opaque
        raise InvalidURIError,
          "can not set port with registry or opaque"
      elsif !v.kind_of?(Integer) && parser.regexp[:PORT] !~ v
        raise InvalidComponentError,
          "bad component(expected port component): #{v.inspect}"
      end

      return true
    end
    private :check_port

    # Protected setter for the port component +v+.
    #
    # See also URI::Generic.port=.
    #
    def set_port(v)
      v = v.empty? ? nil : v.to_i unless !v || v.kind_of?(Integer)
      @port = v
    end
    protected :set_port

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the port component +v+
    # (with validation).
    #
    # See also URI::Generic.check_port.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com")
    #   uri.port = 8080
    #   uri.to_s  #=> "http://my.example.com:8080"
    #
    def port=(v)
      check_port(v)
      set_port(v)
      port
    end

    def check_registry(v) # :nodoc:
      raise InvalidURIError, "can not set registry"
    end
    private :check_registry

    def set_registry(v) #:nodoc:
      raise InvalidURIError, "can not set registry"
    end
    protected :set_registry

    def registry=(v)
      raise InvalidURIError, "can not set registry"
    end

    #
    # Checks the path +v+ component for RFC2396 compliance
    # and against the URI::Parser Regexp
    # for :ABS_PATH and :REL_PATH.
    #
    # Can not have a opaque component defined,
    # with a path component defined.
    #
    def check_path(v)
      # raise if both hier and opaque are not nil, because:
      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      if v && @opaque
        raise InvalidURIError,
          "path conflicts with opaque"
      end

      # If scheme is ftp, path may be relative.
      # See RFC 1738 section 3.2.2, and RFC 2396.
      if @scheme && @scheme != "ftp"
        if v && v != '' && parser.regexp[:ABS_PATH] !~ v
          raise InvalidComponentError,
            "bad component(expected absolute path component): #{v}"
        end
      else
        if v && v != '' && parser.regexp[:ABS_PATH] !~ v &&
           parser.regexp[:REL_PATH] !~ v
          raise InvalidComponentError,
            "bad component(expected relative path component): #{v}"
        end
      end

      return true
    end
    private :check_path

    # Protected setter for the path component +v+.
    #
    # See also URI::Generic.path=.
    #
    def set_path(v)
      @path = v
    end
    protected :set_path

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the path component +v+
    # (with validation).
    #
    # See also URI::Generic.check_path.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com/pub/files")
    #   uri.path = "/faq/"
    #   uri.to_s  #=> "http://my.example.com/faq/"
    #
    def path=(v)
      check_path(v)
      set_path(v)
      v
    end

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the query component +v+.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com/?id=25")
    #   uri.query = "id=1"
    #   uri.to_s  #=> "http://my.example.com/?id=1"
    #
    def query=(v)
      return @query = nil unless v
      raise InvalidURIError, "query conflicts with opaque" if @opaque

      x = v.to_str
      v = x.dup if x.equal? v
      v.encode!(Encoding::UTF_8) rescue nil
      v.delete!("\t\r\n")
      v.force_encoding(Encoding::ASCII_8BIT)
      raise InvalidURIError, "invalid percent escape: #{$1}" if /(%\H\H)/n.match(v)
      v.gsub!(/(?!%\h\h|[!$-&(-;=?-_a-~])./n.freeze){'%%%02X' % $&.ord}
      v.force_encoding(Encoding::US_ASCII)
      @query = v
    end

    #
    # Checks the opaque +v+ component for RFC2396 compliance and
    # against the URI::Parser Regexp for :OPAQUE.
    #
    # Can not have a host, port, user, or path component defined,
    # with an opaque component defined.
    #
    def check_opaque(v)
      return v unless v

      # raise if both hier and opaque are not nil, because:
      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      if @host || @port || @user || @path  # userinfo = @user + ':' + @password
        raise InvalidURIError,
          "can not set opaque with host, port, userinfo or path"
      elsif v && parser.regexp[:OPAQUE] !~ v
        raise InvalidComponentError,
          "bad component(expected opaque component): #{v}"
      end

      return true
    end
    private :check_opaque

    # Protected setter for the opaque component +v+.
    #
    # See also URI::Generic.opaque=.
    #
    def set_opaque(v)
      @opaque = v
    end
    protected :set_opaque

    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the opaque component +v+
    # (with validation).
    #
    # See also URI::Generic.check_opaque.
    #
    def opaque=(v)
      check_opaque(v)
      set_opaque(v)
      v
    end

    #
    # Checks the fragment +v+ component against the URI::Parser Regexp for :FRAGMENT.
    #
    #
    # == Args
    #
    # +v+::
    #    String
    #
    # == Description
    #
    # Public setter for the fragment component +v+
    # (with validation).
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com/?id=25#time=1305212049")
    #   uri.fragment = "time=1305212086"
    #   uri.to_s  #=> "http://my.example.com/?id=25#time=1305212086"
    #
    def fragment=(v)
      return @fragment = nil unless v

      x = v.to_str
      v = x.dup if x.equal? v
      v.encode!(Encoding::UTF_8) rescue nil
      v.delete!("\t\r\n")
      v.force_encoding(Encoding::ASCII_8BIT)
      v.gsub!(/(?!%\h\h|[!-~])./n){'%%%02X' % $&.ord}
      v.force_encoding(Encoding::US_ASCII)
      @fragment = v
    end

    #
    # Returns true if URI is hierarchical.
    #
    # == Description
    #
    # URI has components listed in order of decreasing significance from left to right,
    # see RFC3986 https://tools.ietf.org/html/rfc3986 1.2.3.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com/")
    #   uri.hierarchical?
    #   #=> true
    #   uri = URI.parse("mailto:joe@example.com")
    #   uri.hierarchical?
    #   #=> false
    #
    def hierarchical?
      if @path
        true
      else
        false
      end
    end

    #
    # Returns true if URI has a scheme (e.g. http:// or https://) specified.
    #
    def absolute?
      if @scheme
        true
      else
        false
      end
    end
    alias absolute absolute?

    #
    # Returns true if URI does not have a scheme (e.g. http:// or https://) specified.
    #
    def relative?
      !absolute?
    end

    #
    # Returns an Array of the path split on '/'.
    #
    def split_path(path)
      path.split("/", -1)
    end
    private :split_path

    #
    # Merges a base path +base+, with relative path +rel+,
    # returns a modified base path.
    #
    def merge_path(base, rel)

      # RFC2396, Section 5.2, 5)
      # RFC2396, Section 5.2, 6)
      base_path = split_path(base)
      rel_path  = split_path(rel)

      # RFC2396, Section 5.2, 6), a)
      base_path << '' if base_path.last == '..'
      while i = base_path.index('..')
        base_path.slice!(i - 1, 2)
      end

      if (first = rel_path.first) and first.empty?
        base_path.clear
        rel_path.shift
      end

      # RFC2396, Section 5.2, 6), c)
      # RFC2396, Section 5.2, 6), d)
      rel_path.push('') if rel_path.last == '.' || rel_path.last == '..'
      rel_path.delete('.')

      # RFC2396, Section 5.2, 6), e)
      tmp = []
      rel_path.each do |x|
        if x == '..' &&
            !(tmp.empty? || tmp.last == '..')
          tmp.pop
        else
          tmp << x
        end
      end

      add_trailer_slash = !tmp.empty?
      if base_path.empty?
        base_path = [''] # keep '/' for root directory
      elsif add_trailer_slash
        base_path.pop
      end
      while x = tmp.shift
        if x == '..'
          # RFC2396, Section 4
          # a .. or . in an absolute path has no special meaning
          base_path.pop if base_path.size > 1
        else
          # if x == '..'
          #   valid absolute (but abnormal) path "/../..."
          # else
          #   valid absolute path
          # end
          base_path << x
          tmp.each {|t| base_path << t}
          add_trailer_slash = false
          break
        end
      end
      base_path.push('') if add_trailer_slash

      return base_path.join('/')
    end
    private :merge_path

    #
    # == Args
    #
    # +oth+::
    #    URI or String
    #
    # == Description
    #
    # Destructive form of #merge.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com")
    #   uri.merge!("/main.rbx?page=1")
    #   uri.to_s  # => "http://my.example.com/main.rbx?page=1"
    #
    def merge!(oth)
      t = merge(oth)
      if self == t
        nil
      else
        replace!(t)
        self
      end
    end

    #
    # == Args
    #
    # +oth+::
    #    URI or String
    #
    # == Description
    #
    # Merges two URIs.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com")
    #   uri.merge("/main.rbx?page=1")
    #   # => "http://my.example.com/main.rbx?page=1"
    #
    def merge(oth)
      rel = parser.__send__(:convert_to_uri, oth)

      if rel.absolute?
        #raise BadURIError, "both URI are absolute" if absolute?
        # hmm... should return oth for usability?
        return rel
      end

      unless self.absolute?
        raise BadURIError, "both URI are relative"
      end

      base = self.dup

      authority = rel.userinfo || rel.host || rel.port

      # RFC2396, Section 5.2, 2)
      if (rel.path.nil? || rel.path.empty?) && !authority && !rel.query
        base.fragment=(rel.fragment) if rel.fragment
        return base
      end

      base.query = nil
      base.fragment=(nil)

      # RFC2396, Section 5.2, 4)
      if !authority
        base.set_path(merge_path(base.path, rel.path)) if base.path && rel.path
      else
        # RFC2396, Section 5.2, 4)
        base.set_path(rel.path) if rel.path
      end

      # RFC2396, Section 5.2, 7)
      base.set_userinfo(rel.userinfo) if rel.userinfo
      base.set_host(rel.host)         if rel.host
      base.set_port(rel.port)         if rel.port
      base.query = rel.query       if rel.query
      base.fragment=(rel.fragment) if rel.fragment

      return base
    end # merge
    alias + merge

    # :stopdoc:
    def route_from_path(src, dst)
      case dst
      when src
        # RFC2396, Section 4.2
        return ''
      when %r{(?:\A|/)\.\.?(?:/|\z)}
        # dst has abnormal absolute path,
        # like "/./", "/../", "/x/../", ...
        return dst.dup
      end

      src_path = src.scan(%r{[^/]*/})
      dst_path = dst.scan(%r{[^/]*/?})

      # discard same parts
      while !dst_path.empty? && dst_path.first == src_path.first
        src_path.shift
        dst_path.shift
      end

      tmp = dst_path.join

      # calculate
      if src_path.empty?
        if tmp.empty?
          return './'
        elsif dst_path.first.include?(':') # (see RFC2396 Section 5)
          return './' + tmp
        else
          return tmp
        end
      end

      return '../' * src_path.size + tmp
    end
    private :route_from_path
    # :startdoc:

    # :stopdoc:
    def route_from0(oth)
      oth = parser.__send__(:convert_to_uri, oth)
      if self.relative?
        raise BadURIError,
          "relative URI: #{self}"
      end
      if oth.relative?
        raise BadURIError,
          "relative URI: #{oth}"
      end

      if self.scheme != oth.scheme
        return self, self.dup
      end
      rel = URI::Generic.new(nil, # it is relative URI
                             self.userinfo, self.host, self.port,
                             nil, self.path, self.opaque,
                             self.query, self.fragment, parser)

      if rel.userinfo != oth.userinfo ||
          rel.host.to_s.downcase != oth.host.to_s.downcase ||
          rel.port != oth.port

        if self.userinfo.nil? && self.host.nil?
          return self, self.dup
        end

        rel.set_port(nil) if rel.port == oth.default_port
        return rel, rel
      end
      rel.set_userinfo(nil)
      rel.set_host(nil)
      rel.set_port(nil)

      if rel.path && rel.path == oth.path
        rel.set_path('')
        rel.query = nil if rel.query == oth.query
        return rel, rel
      elsif rel.opaque && rel.opaque == oth.opaque
        rel.set_opaque('')
        rel.query = nil if rel.query == oth.query
        return rel, rel
      end

      # you can modify `rel', but can not `oth'.
      return oth, rel
    end
    private :route_from0
    # :startdoc:

    #
    # == Args
    #
    # +oth+::
    #    URI or String
    #
    # == Description
    #
    # Calculates relative path from oth to self.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse('http://my.example.com/main.rbx?page=1')
    #   uri.route_from('http://my.example.com')
    #   #=> #<URI::Generic /main.rbx?page=1>
    #
    def route_from(oth)
      # you can modify `rel', but can not `oth'.
      begin
        oth, rel = route_from0(oth)
      rescue
        raise $!.class, $!.message
      end
      if oth == rel
        return rel
      end

      rel.set_path(route_from_path(oth.path, self.path))
      if rel.path == './' && self.query
        # "./?foo" -> "?foo"
        rel.set_path('')
      end

      return rel
    end

    alias - route_from

    #
    # == Args
    #
    # +oth+::
    #    URI or String
    #
    # == Description
    #
    # Calculates relative path to oth from self.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse('http://my.example.com')
    #   uri.route_to('http://my.example.com/main.rbx?page=1')
    #   #=> #<URI::Generic /main.rbx?page=1>
    #
    def route_to(oth)
      parser.__send__(:convert_to_uri, oth).route_from(self)
    end

    #
    # Returns normalized URI.
    #
    #   require 'uri'
    #
    #   URI("HTTP://my.EXAMPLE.com").normalize
    #   #=> #<URI::HTTP http://my.example.com/>
    #
    # Normalization here means:
    #
    # * scheme and host are converted to lowercase,
    # * an empty path component is set to "/".
    #
    def normalize
      uri = dup
      uri.normalize!
      uri
    end

    #
    # Destructive version of #normalize.
    #
    def normalize!
      if path&.empty?
        set_path('/')
      end
      if scheme && scheme != scheme.downcase
        set_scheme(self.scheme.downcase)
      end
      if host && host != host.downcase
        set_host(self.host.downcase)
      end
    end

    #
    # Constructs String from URI.
    #
    def to_s
      str = ''.dup
      if @scheme
        str << @scheme
        str << ':'
      end

      if @opaque
        str << @opaque
      else
        if @host || %w[file postgres].include?(@scheme)
          str << '//'
        end
        if self.userinfo
          str << self.userinfo
          str << '@'
        end
        if @host
          str << @host
        end
        if @port && @port != self.default_port
          str << ':'
          str << @port.to_s
        end
        str << @path
        if @query
          str << '?'
          str << @query
        end
      end
      if @fragment
        str << '#'
        str << @fragment
      end
      str
    end
    alias to_str to_s

    #
    # Compares two URIs.
    #
    def ==(oth)
      if self.class == oth.class
        self.normalize.component_ary == oth.normalize.component_ary
      else
        false
      end
    end

    def hash
      self.component_ary.hash
    end

    def eql?(oth)
      self.class == oth.class &&
      parser == oth.parser &&
      self.component_ary.eql?(oth.component_ary)
    end

=begin

--- URI::Generic#===(oth)

=end
#    def ===(oth)
#      raise NotImplementedError
#    end

=begin
=end


    # Returns an Array of the components defined from the COMPONENT Array.
    def component_ary
      component.collect do |x|
        self.__send__(x)
      end
    end
    protected :component_ary

    # == Args
    #
    # +components+::
    #    Multiple Symbol arguments defined in URI::HTTP.
    #
    # == Description
    #
    # Selects specified components from URI.
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse('http://myuser:mypass@my.example.com/test.rbx')
    #   uri.select(:userinfo, :host, :path)
    #   # => ["myuser:mypass", "my.example.com", "/test.rbx"]
    #
    def select(*components)
      components.collect do |c|
        if component.include?(c)
          self.__send__(c)
        else
          raise ArgumentError,
            "expected of components of #{self.class} (#{self.class.component.join(', ')})"
        end
      end
    end

    def inspect
      "#<#{self.class} #{self}>"
    end

    #
    # == Args
    #
    # +v+::
    #    URI or String
    #
    # == Description
    #
    # Attempts to parse other URI +oth+,
    # returns [parsed_oth, self].
    #
    # == Usage
    #
    #   require 'uri'
    #
    #   uri = URI.parse("http://my.example.com")
    #   uri.coerce("http://foo.com")
    #   #=> [#<URI::HTTP http://foo.com>, #<URI::HTTP http://my.example.com>]
    #
    def coerce(oth)
      case oth
      when String
        oth = parser.parse(oth)
      else
        super
      end

      return oth, self
    end

    # Returns a proxy URI.
    # The proxy URI is obtained from environment variables such as http_proxy,
    # ftp_proxy, no_proxy, etc.
    # If there is no proper proxy, nil is returned.
    #
    # If the optional parameter +env+ is specified, it is used instead of ENV.
    #
    # Note that capitalized variables (HTTP_PROXY, FTP_PROXY, NO_PROXY, etc.)
    # are examined, too.
    #
    # But http_proxy and HTTP_PROXY is treated specially under CGI environment.
    # It's because HTTP_PROXY may be set by Proxy: header.
    # So HTTP_PROXY is not used.
    # http_proxy is not used too if the variable is case insensitive.
    # CGI_HTTP_PROXY can be used instead.
    def find_proxy(env=ENV)
      raise BadURIError, "relative URI: #{self}" if self.relative?
      name = self.scheme.downcase + '_proxy'
      proxy_uri = nil
      if name == 'http_proxy' && env.include?('REQUEST_METHOD') # CGI?
        # HTTP_PROXY conflicts with *_proxy for proxy settings and
        # HTTP_* for header information in CGI.
        # So it should be careful to use it.
        pairs = env.reject {|k, v| /\Ahttp_proxy\z/i !~ k }
        case pairs.length
        when 0 # no proxy setting anyway.
          proxy_uri = nil
        when 1
          k, _ = pairs.shift
          if k == 'http_proxy' && env[k.upcase] == nil
            # http_proxy is safe to use because ENV is case sensitive.
            proxy_uri = env[name]
          else
            proxy_uri = nil
          end
        else # http_proxy is safe to use because ENV is case sensitive.
          proxy_uri = env.to_hash[name]
        end
        if !proxy_uri
          # Use CGI_HTTP_PROXY.  cf. libwww-perl.
          proxy_uri = env["CGI_#{name.upcase}"]
        end
      elsif name == 'http_proxy'
        if RUBY_ENGINE == 'jruby' && p_addr = ENV_JAVA['http.proxyHost']
          p_port = ENV_JAVA['http.proxyPort']
          if p_user = ENV_JAVA['http.proxyUser']
            p_pass = ENV_JAVA['http.proxyPass']
            proxy_uri = "http://#{p_user}:#{p_pass}@#{p_addr}:#{p_port}"
          else
            proxy_uri = "http://#{p_addr}:#{p_port}"
          end
        else
          unless proxy_uri = env[name]
            if proxy_uri = env[name.upcase]
              warn 'The environment variable HTTP_PROXY is discouraged.  Use http_proxy.', uplevel: 1
            end
          end
        end
      else
        proxy_uri = env[name] || env[name.upcase]
      end

      if proxy_uri.nil? || proxy_uri.empty?
        return nil
      end

      if self.hostname
        begin
          addr = IPSocket.getaddress(self.hostname)
          return nil if /\A127\.|\A::1\z/ =~ addr
        rescue SocketError
        end
      end

      name = 'no_proxy'
      if no_proxy = env[name] || env[name.upcase]
        return nil unless URI::Generic.use_proxy?(self.hostname, addr, self.port, no_proxy)
      end
      URI.parse(proxy_uri)
    end

    def self.use_proxy?(hostname, addr, port, no_proxy) # :nodoc:
      hostname = hostname.downcase
      dothostname = ".#{hostname}"
      no_proxy.scan(/([^:,\s]+)(?::(\d+))?/) {|p_host, p_port|
        if !p_port || port == p_port.to_i
          if p_host.start_with?('.')
            return false if hostname.end_with?(p_host.downcase)
          else
            return false if dothostname.end_with?(".#{p_host.downcase}")
          end
          if addr
            begin
              return false if IPAddr.new(p_host).include?(addr)
            rescue IPAddr::InvalidAddressError
              next
            end
          end
        end
      }
      true
    end
  end
end
