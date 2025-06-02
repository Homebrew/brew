# frozen_string_literal: true
require_relative 'util'
class CGI
  # Class representing an HTTP cookie.
  #
  # In addition to its specific fields and methods, a Cookie instance
  # is a delegator to the array of its values.
  #
  # See RFC 2965.
  #
  # == Examples of use
  #   cookie1 = CGI::Cookie.new("name", "value1", "value2", ...)
  #   cookie1 = CGI::Cookie.new("name" => "name", "value" => "value")
  #   cookie1 = CGI::Cookie.new('name'     => 'name',
  #                             'value'    => ['value1', 'value2', ...],
  #                             'path'     => 'path',   # optional
  #                             'domain'   => 'domain', # optional
  #                             'expires'  => Time.now, # optional
  #                             'secure'   => true,     # optional
  #                             'httponly' => true      # optional
  #                             )
  #
  #   cgi.out("cookie" => [cookie1, cookie2]) { "string" }
  #
  #   name     = cookie1.name
  #   values   = cookie1.value
  #   path     = cookie1.path
  #   domain   = cookie1.domain
  #   expires  = cookie1.expires
  #   secure   = cookie1.secure
  #   httponly = cookie1.httponly
  #
  #   cookie1.name     = 'name'
  #   cookie1.value    = ['value1', 'value2', ...]
  #   cookie1.path     = 'path'
  #   cookie1.domain   = 'domain'
  #   cookie1.expires  = Time.now + 30
  #   cookie1.secure   = true
  #   cookie1.httponly = true
  class Cookie < Array
    @@accept_charset="UTF-8" unless defined?(@@accept_charset)

    TOKEN_RE = %r"\A[[!-~]&&[^()<>@,;:\\\"/?=\[\]{}]]+\z"
    PATH_VALUE_RE = %r"\A[[ -~]&&[^;]]*\z"
    DOMAIN_VALUE_RE = %r"\A\.?(?<label>(?!-)[-A-Za-z0-9]+(?<!-))(?:\.\g<label>)*\z"

    # Create a new CGI::Cookie object.
    #
    # :call-seq:
    #   Cookie.new(name_string,*value)
    #   Cookie.new(options_hash)
    #
    # +name_string+::
    #   The name of the cookie; in this form, there is no #domain or
    #   #expiration.  The #path is gleaned from the +SCRIPT_NAME+ environment
    #   variable, and #secure is false.
    # <tt>*value</tt>::
    #   value or list of values of the cookie
    # +options_hash+::
    #   A Hash of options to initialize this Cookie.  Possible options are:
    #
    #   name:: the name of the cookie.  Required.
    #   value:: the cookie's value or list of values.
    #   path:: the path for which this cookie applies.  Defaults to
    #          the value of the +SCRIPT_NAME+ environment variable.
    #   domain:: the domain for which this cookie applies.
    #   expires:: the time at which this cookie expires, as a +Time+ object.
    #   secure:: whether this cookie is a secure cookie or not (default to
    #            false).  Secure cookies are only transmitted to HTTPS
    #            servers.
    #   httponly:: whether this cookie is a HttpOnly cookie or not (default to
    #            false).  HttpOnly cookies are not available to javascript.
    #
    #   These keywords correspond to attributes of the cookie object.
    def initialize(name = "", *value)
      @domain = nil
      @expires = nil
      if name.kind_of?(String)
        self.name = name
        self.path = (%r|\A(.*/)| =~ ENV["SCRIPT_NAME"] ? $1 : "")
        @secure = false
        @httponly = false
        return super(value)
      end

      options = name
      unless options.has_key?("name")
        raise ArgumentError, "`name' required"
      end

      self.name = options["name"]
      value = Array(options["value"])
      # simple support for IE
      self.path = options["path"] || (%r|\A(.*/)| =~ ENV["SCRIPT_NAME"] ? $1 : "")
      self.domain = options["domain"]
      @expires = options["expires"]
      @secure = options["secure"] == true
      @httponly = options["httponly"] == true

      super(value)
    end

    # Name of this cookie, as a +String+
    attr_reader :name
    # Set name of this cookie
    def name=(str)
      if str and !TOKEN_RE.match?(str)
        raise ArgumentError, "invalid name: #{str.dump}"
      end
      @name = str
    end

    # Path for which this cookie applies, as a +String+
    attr_reader :path
    # Set path for which this cookie applies
    def path=(str)
      if str and !PATH_VALUE_RE.match?(str)
        raise ArgumentError, "invalid path: #{str.dump}"
      end
      @path = str
    end

    # Domain for which this cookie applies, as a +String+
    attr_reader :domain
    # Set domain for which this cookie applies
    def domain=(str)
      if str and ((str = str.b).bytesize > 255 or !DOMAIN_VALUE_RE.match?(str))
        raise ArgumentError, "invalid domain: #{str.dump}"
      end
      @domain = str
    end

    # Time at which this cookie expires, as a +Time+
    attr_accessor :expires
    # True if this cookie is secure; false otherwise
    attr_reader :secure
    # True if this cookie is httponly; false otherwise
    attr_reader :httponly

    # Returns the value or list of values for this cookie.
    def value
      self
    end

    # Replaces the value of this cookie with a new value or list of values.
    def value=(val)
      replace(Array(val))
    end

    # Set whether the Cookie is a secure cookie or not.
    #
    # +val+ must be a boolean.
    def secure=(val)
      @secure = val if val == true or val == false
      @secure
    end

    # Set whether the Cookie is a httponly cookie or not.
    #
    # +val+ must be a boolean.
    def httponly=(val)
      @httponly = !!val
    end

    # Convert the Cookie to its string representation.
    def to_s
      val = collect{|v| CGI.escape(v) }.join("&")
      buf = "#{@name}=#{val}".dup
      buf << "; domain=#{@domain}" if @domain
      buf << "; path=#{@path}"     if @path
      buf << "; expires=#{CGI.rfc1123_date(@expires)}" if @expires
      buf << "; secure"            if @secure
      buf << "; HttpOnly"          if @httponly
      buf
    end

    # Parse a raw cookie string into a hash of cookie-name=>Cookie
    # pairs.
    #
    #   cookies = CGI::Cookie.parse("raw_cookie_string")
    #     # { "name1" => cookie1, "name2" => cookie2, ... }
    #
    def self.parse(raw_cookie)
      cookies = Hash.new([])
      return cookies unless raw_cookie

      raw_cookie.split(/;\s?/).each do |pairs|
        name, values = pairs.split('=',2)
        next unless name and values
        values ||= ""
        values = values.split('&').collect{|v| CGI.unescape(v,@@accept_charset) }
        if cookies.has_key?(name)
          values = cookies[name].value + values
        end
        cookies[name] = Cookie.new(name, *values)
      end

      cookies
    end

    # A summary of cookie string.
    def inspect
      "#<CGI::Cookie: #{self.to_s.inspect}>"
    end

  end # class Cookie
end


