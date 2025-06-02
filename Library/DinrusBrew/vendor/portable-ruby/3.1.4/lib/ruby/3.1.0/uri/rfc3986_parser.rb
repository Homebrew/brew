# frozen_string_literal: false
module URI
  class RFC3986_Parser # :nodoc:
    # URI defined in RFC3986
    RFC3986_URI = /\A(?<URI>(?<scheme>[A-Za-z][+\-.0-9A-Za-z]*+):(?<hier-part>\/\/(?<authority>(?:(?<userinfo>(?:%\h\h|[!$&-.0-;=A-Z_a-z~])*+)@)?(?<host>(?<IP-literal>\[(?:(?<IPv6address>(?:\h{1,4}:){6}(?<ls32>\h{1,4}:\h{1,4}|(?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)\.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>))|::(?:\h{1,4}:){5}\g<ls32>|\h{1,4}?::(?:\h{1,4}:){4}\g<ls32>|(?:(?:\h{1,4}:)?\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>|(?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>|(?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>|(?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>|(?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}|(?:(?:\h{1,4}:){,6}\h{1,4})?::)|(?<IPvFuture>v\h++\.[!$&-.0-;=A-Z_a-z~]++))\])|\g<IPv4address>|(?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])*+))(?::(?<port>\d*+))?)(?<path-abempty>(?:\/(?<segment>(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*+))*+)|(?<path-absolute>\/(?:(?<segment-nz>(?:%\h\h|[!$&-.0-;=@-Z_a-z~])++)(?:\/\g<segment>)*+)?)|(?<path-rootless>\g<segment-nz>(?:\/\g<segment>)*+)|(?<path-empty>))(?:\?(?<query>[^#]*+))?(?:\#(?<fragment>(?:%\h\h|[!$&-.0-;=@-Z_a-z~\/?])*+))?)\z/
    RFC3986_relative_ref = /\A(?<relative-ref>(?<relative-part>\/\/(?<authority>(?:(?<userinfo>(?:%\h\h|[!$&-.0-;=A-Z_a-z~])*+)@)?(?<host>(?<IP-literal>\[(?:(?<IPv6address>(?:\h{1,4}:){6}(?<ls32>\h{1,4}:\h{1,4}|(?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)\.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>))|::(?:\h{1,4}:){5}\g<ls32>|\h{1,4}?::(?:\h{1,4}:){4}\g<ls32>|(?:(?:\h{1,4}:){,1}\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>|(?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>|(?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>|(?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>|(?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}|(?:(?:\h{1,4}:){,6}\h{1,4})?::)|(?<IPvFuture>v\h++\.[!$&-.0-;=A-Z_a-z~]++))\])|\g<IPv4address>|(?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])++))?(?::(?<port>\d*+))?)(?<path-abempty>(?:\/(?<segment>(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*+))*+)|(?<path-absolute>\/(?:(?<segment-nz>(?:%\h\h|[!$&-.0-;=@-Z_a-z~])++)(?:\/\g<segment>)*+)?)|(?<path-noscheme>(?<segment-nz-nc>(?:%\h\h|[!$&-.0-9;=@-Z_a-z~])++)(?:\/\g<segment>)*+)|(?<path-empty>))(?:\?(?<query>[^#]*+))?(?:\#(?<fragment>(?:%\h\h|[!$&-.0-;=@-Z_a-z~\/?])*+))?)\z/
    attr_reader :regexp

    def initialize
      @regexp = default_regexp.each_value(&:freeze).freeze
    end

    def split(uri) #:nodoc:
      begin
        uri = uri.to_str
      rescue NoMethodError
        raise InvalidURIError, "bad URI(is not URI?): #{uri.inspect}"
      end
      uri.ascii_only? or
        raise InvalidURIError, "URI must be ascii only #{uri.dump}"
      if m = RFC3986_URI.match(uri)
        query = m["query".freeze]
        scheme = m["scheme".freeze]
        opaque = m["path-rootless".freeze]
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
            m["fragment".freeze]
          ]
        else # normal
          [ scheme,
            m["userinfo".freeze],
            m["host".freeze],
            m["port".freeze],
            nil, # registry
            (m["path-abempty".freeze] ||
             m["path-absolute".freeze] ||
             m["path-empty".freeze]),
            nil, # opaque
            query,
            m["fragment".freeze]
          ]
        end
      elsif m = RFC3986_relative_ref.match(uri)
        [ nil, # scheme
          m["userinfo".freeze],
          m["host".freeze],
          m["port".freeze],
          nil, # registry,
          (m["path-abempty".freeze] ||
           m["path-absolute".freeze] ||
           m["path-noscheme".freeze] ||
           m["path-empty".freeze]),
          nil, # opaque
          m["query".freeze],
          m["fragment".freeze]
        ]
      else
        raise InvalidURIError, "bad URI(is not URI?): #{uri.inspect}"
      end
    end

    def parse(uri) # :nodoc:
      URI.for(*self.split(uri), self)
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
        SCHEME: /\A[A-Za-z][A-Za-z0-9+\-.]*\z/,
        USERINFO: /\A(?:%\h\h|[!$&-.0-;=A-Z_a-z~])*\z/,
        HOST: /\A(?:(?<IP-literal>\[(?:(?<IPv6address>(?:\h{1,4}:){6}(?<ls32>\h{1,4}:\h{1,4}|(?<IPv4address>(?<dec-octet>[1-9]\d|1\d{2}|2[0-4]\d|25[0-5]|\d)\.\g<dec-octet>\.\g<dec-octet>\.\g<dec-octet>))|::(?:\h{1,4}:){5}\g<ls32>|\h{,4}::(?:\h{1,4}:){4}\g<ls32>|(?:(?:\h{1,4}:)?\h{1,4})?::(?:\h{1,4}:){3}\g<ls32>|(?:(?:\h{1,4}:){,2}\h{1,4})?::(?:\h{1,4}:){2}\g<ls32>|(?:(?:\h{1,4}:){,3}\h{1,4})?::\h{1,4}:\g<ls32>|(?:(?:\h{1,4}:){,4}\h{1,4})?::\g<ls32>|(?:(?:\h{1,4}:){,5}\h{1,4})?::\h{1,4}|(?:(?:\h{1,4}:){,6}\h{1,4})?::)|(?<IPvFuture>v\h+\.[!$&-.0-;=A-Z_a-z~]+))\])|\g<IPv4address>|(?<reg-name>(?:%\h\h|[!$&-.0-9;=A-Z_a-z~])*))\z/,
        ABS_PATH: /\A\/(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*(?:\/(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*)*\z/,
        REL_PATH: /\A(?:%\h\h|[!$&-.0-;=@-Z_a-z~])+(?:\/(?:%\h\h|[!$&-.0-;=@-Z_a-z~])*)*\z/,
        QUERY: /\A(?:%\h\h|[!$&-.0-;=@-Z_a-z~\/?])*\z/,
        FRAGMENT: /\A(?:%\h\h|[!$&-.0-;=@-Z_a-z~\/?])*\z/,
        OPAQUE: /\A(?:[^\/].*)?\z/,
        PORT: /\A[\x09\x0a\x0c\x0d ]*\d*[\x09\x0a\x0c\x0d ]*\z/,
      }
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
