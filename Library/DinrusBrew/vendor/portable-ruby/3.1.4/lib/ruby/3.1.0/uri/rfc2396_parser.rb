# frozen_string_literal: false
#--
# = uri/common.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License::
#   You can redistribute it and/or modify it under the same term as Ruby.
#
# See URI for general documentation
#

module URI
  #
  # Includes URI::REGEXP::PATTERN
  #
  module RFC2396_REGEXP
    #
    # Patterns used to parse URI's
    #
    module PATTERN
      # :stopdoc:

      # RFC 2396 (URI Generic Syntax)
      # RFC 2732 (IPv6 Literal Addresses in URL's)
      # RFC 2373 (IPv6 Addressing Architecture)

      # alpha         = lowalpha | upalpha
      ALPHA = "a-zA-Z"
      # alphanum      = alpha | digit
      ALNUM = "#{ALPHA}\\d"

      # hex           = digit | "A" | "B" | "C" | "D" | "E" | "F" |
      #                         "a" | "b" | "c" | "d" | "e" | "f"
      HEX     = "a-fA-F\\d"
      # escaped       = "%" hex hex
      ESCAPED = "%[#{HEX}]{2}"
      # mark          = "-" | "_" | "." | "!" | "~" | "*" | "'" |
      #                 "(" | ")"
      # unreserved    = alphanum | mark
      UNRESERVED = "\\-_.!~*'()#{ALNUM}"
      # reserved      = ";" | "/" | "?" | ":" | "@" | "&" | "=" | "+" |
      #                 "$" | ","
      # reserved      = ";" | "/" | "?" | ":" | "@" | "&" | "=" | "+" |
      #                 "$" | "," | "[" | "]" (RFC 2732)
      RESERVED = ";/?:@&=+$,\\[\\]"

      # domainlabel   = alphanum | alphanum *( alphanum | "-" ) alphanum
      DOMLABEL = "(?:[#{ALNUM}](?:[-#{ALNUM}]*[#{ALNUM}])?)"
      # toplabel      = alpha | alpha *( alphanum | "-" ) alphanum
      TOPLABEL = "(?:[#{ALPHA}](?:[-#{ALNUM}]*[#{ALNUM}])?)"
      # hostname      = *( domainlabel "." ) toplabel [ "." ]
      HOSTNAME = "(?:#{DOMLABEL}\\.)*#{TOPLABEL}\\.?"

      # :startdoc:
    end # PATTERN

    # :startdoc:
  end # REGEXP

  # Class that parses String's into URI's.
  #
  # It contains a Hash set of patterns and Regexp's that match and validate.
  #
  class RFC2396_Parser
    include RFC2396_REGEXP

    #
    # == Synopsis
    #
    #   URI::Parser.new([opts])
    #
    # == Args
    #
    # The constructor accepts a hash as options for parser.
    # Keys of options are pattern names of URI components
    # and values of options are pattern strings.
    # The constructor generates set of regexps for parsing URIs.
    #
    # You can use the following keys:
    #
    #   * :ESCAPED (URI::PATTERN::ESCAPED in default)
    #   * :UNRESERVED (URI::PATTERN::UNRESERVED in default)
    #   * :DOMLABEL (URI::PATTERN::DOMLABEL in default)
    #   * :TOPLABEL (URI::PATTERN::TOPLABEL in default)
    #   * :HOSTNAME (URI::PATTERN::HOSTNAME in default)
    #
    # == Examples
    #
    #   p = URI::Parser.new(:ESCAPED => "(?:%[a-fA-F0-9]{2}|%u[a-fA-F0-9]{4})")
    #   u = p.parse("http://example.jp/%uABCD") #=> #<URI::HTTP http://example.jp/%uABCD>
    #   URI.parse(u.to_s) #=> raises URI::InvalidURIError
    #
    #   s = "http://example.com/ABCD"
    #   u1 = p.parse(s) #=> #<URI::HTTP http://example.com/ABCD>
    #   u2 = URI.parse(s) #=> #<URI::HTTP http://example.com/ABCD>
    #   u1 == u2 #=> true
    #   u1.eql?(u2) #=> false
    #
    def initialize(opts = {})
      @pattern = initialize_pattern(opts)
      @pattern.each_value(&:freeze)
      @pattern.freeze

      @regexp = initialize_regexp(@pattern)
      @regexp.each_value(&:freeze)
      @regexp.freeze
    end

    # The Hash of patterns.
    #
    # See also URI::Parser.initialize_pattern.
    attr_reader :pattern

    # The Hash of Regexp.
    #
    # See also URI::Parser.initialize_regexp.
    attr_reader :regexp

    # Returns a split URI against +regexp[:ABS_URI]+.
    def split(uri)
      case uri
      when ''
        # null uri

      when @regexp[:ABS_URI]
        scheme, opaque, userinfo, host, port,
          registry, path, query, fragment = $~[1..-1]

        # URI-reference = [ absoluteURI | relativeURI ] [ "#" fragment ]

        # absoluteURI   = scheme ":" ( hier_part | opaque_part )
        # hier_part     = ( net_path | abs_path ) [ "?" query ]
        # opaque_part   = uric_no_slash *uric

        # abs_path      = "/"  path_segments
        # net_path      = "//" authority [ abs_path ]

        # authority     = server | reg_name
        # server        = [ [ userinfo "@" ] hostport ]

        if !scheme
          raise InvalidURIError,
            "bad URI(absolute but no scheme): #{uri}"
        end
        if !opaque && (!path && (!host && !registry))
          raise InvalidURIError,
            "bad URI(absolute but no path): #{uri}"
        end

      when @regexp[:REL_URI]
        scheme = nil
        opaque = nil

        userinfo, host, port, registry,
          rel_segment, abs_path, query, fragment = $~[1..-1]
        if rel_segment && abs_path
          path = rel_segment + abs_path
        elsif rel_segment
          path = rel_segment
        elsif abs_path
          path = abs_path
        end

        # URI-reference = [ absoluteURI | relativeURI ] [ "#" fragment ]

        # relativeURI   = ( net_path | abs_path | rel_path ) [ "?" query ]

        # net_path      = "//" authority [ abs_path ]
        # abs_path      = "/"  path_segments
        # rel_path      = rel_segment [ abs_path ]

        # authority     = server | reg_name
        # server        = [ [ userinfo "@" ] hostport ]

      else
        raise InvalidURIError, "bad URI(is not URI?): #{uri}"
      end

      path = '' if !path && !opaque # (see RFC2396 Section 5.2)
      ret = [
        scheme,
        userinfo, host, port,         # X
        registry,                     # X
        path,                         # Y
        opaque,                       # Y
        query,
        fragment
      ]
      return ret
    end

    #
    # == Args
    #
    # +uri+::
    #    String
    #
    # == Description
    #
    # Parses +uri+ and constructs either matching URI scheme object
    # (File, FTP, HTTP, HTTPS, LDAP, LDAPS, or MailTo) or URI::Generic.
    #
    # == Usage
    #
    #   p = URI::Parser.new
    #   p.parse("ldap://ldap.example.com/dc=example?user=john")
    #   #=> #<URI::LDAP ldap://ldap.example.com/dc=example?user=john>
    #
    def parse(uri)
      URI.for(*self.split(uri), self)
    end

    #
    # == Args
    #
    # +uris+::
    #    an Array of Strings
    #
    # == Description
    #
    # Attempts to parse and merge a set of URIs.
    #
    def join(*uris)
      uris[0] = convert_to_uri(uris[0])
      uris.inject :merge
    end

    #
    # :call-seq:
    #   extract( str )
    #   extract( str, schemes )
    #   extract( str, schemes ) {|item| block }
    #
    # == Args
    #
    # +str+::
    #    String to search
    # +schemes+::
    #    Patterns to apply to +str+
    #
    # == Description
    #
    # Attempts to parse and merge a set of URIs.
    # If no +block+ given, then returns the result,
    # else it calls +block+ for each element in result.
    #
    # See also URI::Parser.make_regexp.
    #
    def extract(str, schemes = nil)
      if block_given?
        str.scan(make_regexp(schemes)) { yield $& }
        nil
      else
        result = []
        str.scan(make_regexp(schemes)) { result.push $& }
        result
      end
    end

    # Returns Regexp that is default +self.regexp[:ABS_URI_REF]+,
    # unless +schemes+ is provided. Then it is a Regexp.union with +self.pattern[:X_ABS_URI]+.
    def make_regexp(schemes = nil)
      unless schemes
        @regexp[:ABS_URI_REF]
      else
        /(?=#{Regexp.union(*schemes)}:)#{@pattern[:X_ABS_URI]}/x
      end
    end

    #
    # :call-seq:
    #   escape( str )
    #   escape( str, unsafe )
    #
    # == Args
    #
    # +str+::
    #    String to make safe
    # +unsafe+::
    #    Regexp to apply. Defaults to +self.regexp[:UNSAFE]+
    #
    # == Description
    #
    # Constructs a safe String from +str+, removing unsafe characters,
    # replacing them with codes.
    #
    def escape(str, unsafe = @regexp[:UNSAFE])
      unless unsafe.kind_of?(Regexp)
        # perhaps unsafe is String object
        unsafe = Regexp.new("[#{Regexp.quote(unsafe)}]", false)
      end
      str.gsub(unsafe) do
        us = $&
        tmp = ''
        us.each_byte do |uc|
          tmp << sprintf('%%%02X', uc)
        end
        tmp
      end.force_encoding(Encoding::US_ASCII)
    end

    #
    # :call-seq:
    #   unescape( str )
    #   unescape( str, escaped )
    #
    # == Args
    #
    # +str+::
    #    String to remove escapes from
    # +escaped+::
    #    Regexp to apply. Defaults to +self.regexp[:ESCAPED]+
    #
    # == Description
    #
    # Removes escapes from +str+.
    #
    def unescape(str, escaped = @regexp[:ESCAPED])
      enc = str.encoding
      enc = Encoding::UTF_8 if enc == Encoding::US_ASCII
      str.gsub(escaped) { [$&[1, 2]].pack('H2').force_encoding(enc) }
    end

    @@to_s = Kernel.instance_method(:to_s)
    if @@to_s.respond_to?(:bind_call)
      def inspect
        @@to_s.bind_call(self)
      end
    else
      def inspect
        @@to_s.bind(self).call
      end
    end

    private

    # Constructs the default Hash of patterns.
    def initialize_pattern(opts = {})
      ret = {}
      ret[:ESCAPED] = escaped = (opts.delete(:ESCAPED) || PATTERN::ESCAPED)
      ret[:UNRESERVED] = unreserved = opts.delete(:UNRESERVED) || PATTERN::UNRESERVED
      ret[:RESERVED] = reserved = opts.delete(:RESERVED) || PATTERN::RESERVED
      ret[:DOMLABEL] = opts.delete(:DOMLABEL) || PATTERN::DOMLABEL
      ret[:TOPLABEL] = opts.delete(:TOPLABEL) || PATTERN::TOPLABEL
      ret[:HOSTNAME] = hostname = opts.delete(:HOSTNAME)

      # RFC 2396 (URI Generic Syntax)
      # RFC 2732 (IPv6 Literal Addresses in URL's)
      # RFC 2373 (IPv6 Addressing Architecture)

      # uric          = reserved | unreserved | escaped
      ret[:URIC] = uric = "(?:[#{unreserved}#{reserved}]|#{escaped})"
      # uric_no_slash = unreserved | escaped | ";" | "?" | ":" | "@" |
      #                 "&" | "=" | "+" | "$" | ","
      ret[:URIC_NO_SLASH] = uric_no_slash = "(?:[#{unreserved};?:@&=+$,]|#{escaped})"
      # query         = *uric
      ret[:QUERY] = query = "#{uric}*"
      # fragment      = *uric
      ret[:FRAGMENT] = fragment = "#{uric}*"

      # hostname      = *( domainlabel "." ) toplabel [ "." ]
      # reg-name      = *( unreserved / pct-encoded / sub-delims ) # RFC3986
      unless hostname
        ret[:HOSTNAME] = hostname = "(?:[a-zA-Z0-9\\-.]|%\\h\\h)+"
      end

      # RFC 2373, APPENDIX B:
      # IPv6address = hexpart [ ":" IPv4address ]
      # IPv4address   = 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT
      # hexpart = hexseq | hexseq "::" [ hexseq ] | "::" [ hexseq ]
      # hexseq  = hex4 *( ":" hex4)
      # hex4    = 1*4HEXDIG
      #
      # XXX: This definition has a flaw. "::" + IPv4address must be
      # allowed too.  Here is a replacement.
      #
      # IPv4address = 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT "." 1*3DIGIT
      ret[:IPV4ADDR] = ipv4addr = "\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}"
      # hex4     = 1*4HEXDIG
      hex4 = "[#{PATTERN::HEX}]{1,4}"
      # lastpart = hex4 | IPv4address
      lastpart = "(?:#{hex4}|#{ipv4addr})"
      # hexseq1  = *( hex4 ":" ) hex4
      hexseq1 = "(?:#{hex4}:)*#{hex4}"
      # hexseq2  = *( hex4 ":" ) lastpart
      hexseq2 = "(?:#{hex4}:)*#{lastpart}"
      # IPv6address = hexseq2 | [ hexseq1 ] "::" [ hexseq2 ]
      ret[:IPV6ADDR] = ipv6addr = "(?:#{hexseq2}|(?:#{hexseq1})?::(?:#{hexseq2})?)"

      # IPv6prefix  = ( hexseq1 | [ hexseq1 ] "::" [ hexseq1 ] ) "/" 1*2DIGIT
      # unused

      # ipv6reference = "[" IPv6address "]" (RFC 2732)
      ret[:IPV6REF] = ipv6ref = "\\[#{ipv6addr}\\]"

      # host          = hostname | IPv4address
      # host          = hostname | IPv4address | IPv6reference (RFC 2732)
      ret[:HOST] = host = "(?:#{hostname}|#{ipv4addr}|#{ipv6ref})"
      # port          = *digit
      ret[:PORT] = port = '\d*'
      # hostport      = host [ ":" port ]
      ret[:HOSTPORT] = hostport = "#{host}(?::#{port})?"

      # userinfo      = *( unreserved | escaped |
      #                    ";" | ":" | "&" | "=" | "+" | "$" | "," )
      ret[:USERINFO] = userinfo = "(?:[#{unreserved};:&=+$,]|#{escaped})*"

      # pchar         = unreserved | escaped |
      #                 ":" | "@" | "&" | "=" | "+" | "$" | ","
      pchar = "(?:[#{unreserved}:@&=+$,]|#{escaped})"
      # param         = *pchar
      param = "#{pchar}*"
      # segment       = *pchar *( ";" param )
      segment = "#{pchar}*(?:;#{param})*"
      # path_segments = segment *( "/" segment )
      ret[:PATH_SEGMENTS] = path_segments = "#{segment}(?:/#{segment})*"

      # server        = [ [ userinfo "@" ] hostport ]
      server = "(?:#{userinfo}@)?#{hostport}"
      # reg_name      = 1*( unreserved | escaped | "$" | "," |
      #                     ";" | ":" | "@" | "&" | "=" | "+" )
      ret[:REG_NAME] = reg_name = "(?:[#{unreserved}$,;:@&=+]|#{escaped})+"
      # authority     = server | reg_name
      authority = "(?:#{server}|#{reg_name})"

      # rel_segment   = 1*( unreserved | escaped |
      #                     ";" | "@" | "&" | "=" | "+" | "$" | "," )
      ret[:REL_SEGMENT] = rel_segment = "(?:[#{unreserved};@&=+$,]|#{escaped})+"

      # scheme        = alpha *( alpha | digit | "+" | "-" | "." )
      ret[:SCHEME] = scheme = "[#{PATTERN::ALPHA}][\\-+.#{PATTERN::ALPHA}\\d]*"

      # abs_path      = "/"  path_segments
      ret[:ABS_PATH] = abs_path = "/#{path_segments}"
      # rel_path      = rel_segment [ abs_path ]
      ret[:REL_PATH] = rel_path = "#{rel_segment}(?:#{abs_path})?"
      # net_path      = "//" authority [ abs_path ]
      ret[:NET_PATH] = net_path = "//#{authority}(?:#{abs_path})?"

      # hier_part     = ( net_path | abs_path ) [ "?" query ]
      ret[:HIER_PART] = hier_part = "(?:#{net_path}|#{abs_path})(?:\\?(?:#{query}))?"
      # opaque_part   = uric_no_slash *uric
      ret[:OPAQUE_PART] = opaque_part = "#{uric_no_slash}#{uric}*"

      # absoluteURI   = scheme ":" ( hier_part | opaque_part )
      ret[:ABS_URI] = abs_uri = "#{scheme}:(?:#{hier_part}|#{opaque_part})"
      # relativeURI   = ( net_path | abs_path | rel_path ) [ "?" query ]
      ret[:REL_URI] = rel_uri = "(?:#{net_path}|#{abs_path}|#{rel_path})(?:\\?#{query})?"

      # URI-reference = [ absoluteURI | relativeURI ] [ "#" fragment ]
      ret[:URI_REF] = "(?:#{abs_uri}|#{rel_uri})?(?:##{fragment})?"

      ret[:X_ABS_URI] = "
        (#{scheme}):                           (?# 1: scheme)
        (?:
           (#{opaque_part})                    (?# 2: opaque)
        |
           (?:(?:
             //(?:
                 (?:(?:(#{userinfo})@)?        (?# 3: userinfo)
                   (?:(#{host})(?::(\\d*))?))? (?# 4: host, 5: port)
               |
                 (#{reg_name})                 (?# 6: registry)
               )
             |
             (?!//))                           (?# XXX: '//' is the mark for hostport)
             (#{abs_path})?                    (?# 7: path)
           )(?:\\?(#{query}))?                 (?# 8: query)
        )
        (?:\\#(#{fragment}))?                  (?# 9: fragment)
      "

      ret[:X_REL_URI] = "
        (?:
          (?:
            //
            (?:
              (?:(#{userinfo})@)?       (?# 1: userinfo)
                (#{host})?(?::(\\d*))?  (?# 2: host, 3: port)
            |
              (#{reg_name})             (?# 4: registry)
            )
          )
        |
          (#{rel_segment})              (?# 5: rel_segment)
        )?
        (#{abs_path})?                  (?# 6: abs_path)
        (?:\\?(#{query}))?              (?# 7: query)
        (?:\\#(#{fragment}))?           (?# 8: fragment)
      "

      ret
    end

    # Constructs the default Hash of Regexp's.
    def initialize_regexp(pattern)
      ret = {}

      # for URI::split
      ret[:ABS_URI] = Regexp.new('\A\s*' + pattern[:X_ABS_URI] + '\s*\z', Regexp::EXTENDED)
      ret[:REL_URI] = Regexp.new('\A\s*' + pattern[:X_REL_URI] + '\s*\z', Regexp::EXTENDED)

      # for URI::extract
      ret[:URI_REF]     = Regexp.new(pattern[:URI_REF])
      ret[:ABS_URI_REF] = Regexp.new(pattern[:X_ABS_URI], Regexp::EXTENDED)
      ret[:REL_URI_REF] = Regexp.new(pattern[:X_REL_URI], Regexp::EXTENDED)

      # for URI::escape/unescape
      ret[:ESCAPED] = Regexp.new(pattern[:ESCAPED])
      ret[:UNSAFE]  = Regexp.new("[^#{pattern[:UNRESERVED]}#{pattern[:RESERVED]}]")

      # for Generic#initialize
      ret[:SCHEME]   = Regexp.new("\\A#{pattern[:SCHEME]}\\z")
      ret[:USERINFO] = Regexp.new("\\A#{pattern[:USERINFO]}\\z")
      ret[:HOST]     = Regexp.new("\\A#{pattern[:HOST]}\\z")
      ret[:PORT]     = Regexp.new("\\A#{pattern[:PORT]}\\z")
      ret[:OPAQUE]   = Regexp.new("\\A#{pattern[:OPAQUE_PART]}\\z")
      ret[:REGISTRY] = Regexp.new("\\A#{pattern[:REG_NAME]}\\z")
      ret[:ABS_PATH] = Regexp.new("\\A#{pattern[:ABS_PATH]}\\z")
      ret[:REL_PATH] = Regexp.new("\\A#{pattern[:REL_PATH]}\\z")
      ret[:QUERY]    = Regexp.new("\\A#{pattern[:QUERY]}\\z")
      ret[:FRAGMENT] = Regexp.new("\\A#{pattern[:FRAGMENT]}\\z")

      ret
    end

    def convert_to_uri(uri)
      if uri.is_a?(URI::Generic)
        uri
      elsif uri = String.try_convert(uri)
        parse(uri)
      else
        raise ArgumentError,
          "bad argument (expected URI object or URI string)"
      end
    end

  end # class Parser
end # module URI
