# frozen_string_literal: true
module Gem::URI
  class RFC3986_Parser # :nodoc:
    # Gem::URI defined in RFC3986
    HOST = %r[
      (?<IP-literal>\[(?:
          (?<IPv6address>
            (?:\h{1,4}:){6}
            (?<ls32>\h{1,4}:\h{1,4}
            | (?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)
                \.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>)
            )
          | ::(?:\h{1,4}:){5}\g<ls32>
          | \h{1,4}?::(?:\h{1,4}:){4}\g<ls32>
          | (?:(?:\h{1,4}:)?\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>
          | (?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>
          | (?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>
          | (?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>
          | (?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}
          | (?:(?:\h{1,4}:){,6}\h{1,4})?::
          )
        | (?<IPvFuture>v\h++\.[!$&-.0-9:;=A-Z_a-z~]++)
        )\])
    | \g<IPv4address>
    | (?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])*+)
    ]x

    USERINFO = /(?:%\h\h|[!$&-.0-9:;=A-Z_a-z~])*+/

    SCHEME = %r[[A-Za-z][+\-.0-9A-Za-z]*+].source
    SEG = %r[(?:%\h\h|[!$&-.0-9:;=@A-Z_a-z~/])].source
    SEG_NC = %r[(?:%\h\h|[!$&-.0-9;=@A-Z_a-z~])].source
    FRAGMENT = %r[(?:%\h\h|[!$&-.0-9:;=@A-Z_a-z~/?])*+].source

    RFC3986_URI = %r[\A
    (?<seg>#{SEG}){0}
    (?<Gem::URI>
      (?<scheme>#{SCHEME}):
      (?<hier-part>//
        (?<authority>
          (?:(?<userinfo>#{USERINFO.source})@)?
          (?<host>#{HOST.source.delete(" \n")})
          (?::(?<port>\d*+))?
        )
        (?<path-abempty>(?:/\g<seg>*+)?)
      | (?<path-absolute>/((?!/)\g<seg>++)?)
      | (?<path-rootless>(?!/)\g<seg>++)
      | (?<path-empty>)
      )
      (?:\?(?<query>[^\#]*+))?
      (?:\#(?<fragment>#{FRAGMENT}))?
    )\z]x

    RFC3986_relative_ref = %r[\A
    (?<seg>#{SEG}){0}
    (?<relative-ref>
      (?<relative-part>//
        (?<authority>
          (?:(?<userinfo>#{USERINFO.source})@)?
          (?<host>#{HOST.source.delete(" \n")}(?<!/))?
          (?::(?<port>\d*+))?
        )
        (?<path-abempty>(?:/\g<seg>*+)?)
      | (?<path-absolute>/\g<seg>*+)
      | (?<path-noscheme>#{SEG_NC}++(?:/\g<seg>*+)?)
      | (?<path-empty>)
      )
      (?:\?(?<query>[^#]*+))?
      (?:\#(?<fragment>#{FRAGMENT}))?
    )\z]x
    attr_reader :regexp

    def initialize
      @regexp = default_regexp.each_value(&:freeze).freeze
    end

    def split(uri) #:nodoc:
      begin
        uri = uri.to_str
      rescue NoMethodError
        raise InvalidURIError, "bad Gem::URI(is not Gem::URI?): #{uri.inspect}"
      end
      uri.ascii_only? or
        raise InvalidURIError, "Gem::URI must be ascii only #{uri.dump}"
      if m = RFC3986_URI.match(uri)
        query = m["query"]
        scheme = m["scheme"]
        opaque = m["path-rootless"]
        if opaque
          opaque << "?#{query}" if query
          [ scheme,
            nil, # userinfo
            nil, # host
            nil, # port
            nil, # registry
            nil, # path
            opaque,
            nil, # query
            m["fragment"]
          ]
        else # normal
          [ scheme,
            m["userinfo"],
            m["host"],
            m["port"],
            nil, # registry
            (m["path-abempty"] ||
             m["path-absolute"] ||
             m["path-empty"]),
            nil, # opaque
            query,
            m["fragment"]
          ]
        end
      elsif m = RFC3986_relative_ref.match(uri)
        [ nil, # scheme
          m["userinfo"],
          m["host"],
          m["port"],
          nil, # registry,
          (m["path-abempty"] ||
           m["path-absolute"] ||
           m["path-noscheme"] ||
           m["path-empty"]),
          nil, # opaque
          m["query"],
          m["fragment"]
        ]
      else
        raise InvalidURIError, "bad Gem::URI(is not Gem::URI?): #{uri.inspect}"
      end
    end

    def parse(uri) # :nodoc:
      Gem::URI.for(*self.split(uri), self)
    end


    def join(*uris) # :nodoc:
      uris[0] = convert_to_uri(uris[0])
      uris.inject :merge
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

    def default_regexp # :nodoc:
      {
        SCHEME: %r[\A#{SCHEME}\z]o,
        USERINFO: %r[\A#{USERINFO}\z]o,
        HOST: %r[\A#{HOST}\z]o,
        ABS_PATH: %r[\A/#{SEG}*+\z]o,
        REL_PATH: %r[\A(?!/)#{SEG}++\z]o,
        QUERY: %r[\A(?:%\h\h|[!$&-.0-9:;=@A-Z_a-z~/?])*+\z],
        FRAGMENT: %r[\A#{FRAGMENT}\z]o,
        OPAQUE: %r[\A(?:[^/].*)?\z],
        PORT: /\A[\x09\x0a\x0c\x0d ]*+\d*[\x09\x0a\x0c\x0d ]*\z/,
      }
    end

    def convert_to_uri(uri)
      if uri.is_a?(Gem::URI::Generic)
        uri
      elsif uri = String.try_convert(uri)
        parse(uri)
      else
        raise ArgumentError,
          "bad argument (expected Gem::URI object or Gem::URI string)"
      end
    end

  end # class Parser
end # module Gem::URI
