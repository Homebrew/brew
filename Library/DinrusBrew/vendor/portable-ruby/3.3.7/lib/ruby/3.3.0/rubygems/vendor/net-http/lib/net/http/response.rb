# frozen_string_literal: true

# This class is the base class for \Gem::Net::HTTP response classes.
#
# == About the Examples
#
# :include: doc/net-http/examples.rdoc
#
# == Returned Responses
#
# \Method Gem::Net::HTTP.get_response returns
# an instance of one of the subclasses of \Gem::Net::HTTPResponse:
#
#   Gem::Net::HTTP.get_response(uri)
#   # => #<Gem::Net::HTTPOK 200 OK readbody=true>
#   Gem::Net::HTTP.get_response(hostname, '/nosuch')
#   # => #<Gem::Net::HTTPNotFound 404 Not Found readbody=true>
#
# As does method Gem::Net::HTTP#request:
#
#   req = Gem::Net::HTTP::Get.new(uri)
#   Gem::Net::HTTP.start(hostname) do |http|
#     http.request(req)
#   end # => #<Gem::Net::HTTPOK 200 OK readbody=true>
#
# \Class \Gem::Net::HTTPResponse includes module Gem::Net::HTTPHeader,
# which provides access to response header values via (among others):
#
# - \Hash-like method <tt>[]</tt>.
# - Specific reader methods, such as +content_type+.
#
# Examples:
#
#   res = Gem::Net::HTTP.get_response(uri) # => #<Gem::Net::HTTPOK 200 OK readbody=true>
#   res['Content-Type']               # => "text/html; charset=UTF-8"
#   res.content_type                  # => "text/html"
#
# == Response Subclasses
#
# \Class \Gem::Net::HTTPResponse has a subclass for each
# {HTTP status code}[https://en.wikipedia.org/wiki/List_of_HTTP_status_codes].
# You can look up the response class for a given code:
#
#   Gem::Net::HTTPResponse::CODE_TO_OBJ['200'] # => Gem::Net::HTTPOK
#   Gem::Net::HTTPResponse::CODE_TO_OBJ['400'] # => Gem::Net::HTTPBadRequest
#   Gem::Net::HTTPResponse::CODE_TO_OBJ['404'] # => Gem::Net::HTTPNotFound
#
# And you can retrieve the status code for a response object:
#
#   Gem::Net::HTTP.get_response(uri).code                 # => "200"
#   Gem::Net::HTTP.get_response(hostname, '/nosuch').code # => "404"
#
# The response subclasses (indentation shows class hierarchy):
#
# - Gem::Net::HTTPUnknownResponse (for unhandled \HTTP extensions).
#
# - Gem::Net::HTTPInformation:
#
#   - Gem::Net::HTTPContinue (100)
#   - Gem::Net::HTTPSwitchProtocol (101)
#   - Gem::Net::HTTPProcessing (102)
#   - Gem::Net::HTTPEarlyHints (103)
#
# - Gem::Net::HTTPSuccess:
#
#   - Gem::Net::HTTPOK (200)
#   - Gem::Net::HTTPCreated (201)
#   - Gem::Net::HTTPAccepted (202)
#   - Gem::Net::HTTPNonAuthoritativeInformation (203)
#   - Gem::Net::HTTPNoContent (204)
#   - Gem::Net::HTTPResetContent (205)
#   - Gem::Net::HTTPPartialContent (206)
#   - Gem::Net::HTTPMultiStatus (207)
#   - Gem::Net::HTTPAlreadyReported (208)
#   - Gem::Net::HTTPIMUsed (226)
#
# - Gem::Net::HTTPRedirection:
#
#   - Gem::Net::HTTPMultipleChoices (300)
#   - Gem::Net::HTTPMovedPermanently (301)
#   - Gem::Net::HTTPFound (302)
#   - Gem::Net::HTTPSeeOther (303)
#   - Gem::Net::HTTPNotModified (304)
#   - Gem::Net::HTTPUseProxy (305)
#   - Gem::Net::HTTPTemporaryRedirect (307)
#   - Gem::Net::HTTPPermanentRedirect (308)
#
# - Gem::Net::HTTPClientError:
#
#   - Gem::Net::HTTPBadRequest (400)
#   - Gem::Net::HTTPUnauthorized (401)
#   - Gem::Net::HTTPPaymentRequired (402)
#   - Gem::Net::HTTPForbidden (403)
#   - Gem::Net::HTTPNotFound (404)
#   - Gem::Net::HTTPMethodNotAllowed (405)
#   - Gem::Net::HTTPNotAcceptable (406)
#   - Gem::Net::HTTPProxyAuthenticationRequired (407)
#   - Gem::Net::HTTPRequestTimeOut (408)
#   - Gem::Net::HTTPConflict (409)
#   - Gem::Net::HTTPGone (410)
#   - Gem::Net::HTTPLengthRequired (411)
#   - Gem::Net::HTTPPreconditionFailed (412)
#   - Gem::Net::HTTPRequestEntityTooLarge (413)
#   - Gem::Net::HTTPRequestURITooLong (414)
#   - Gem::Net::HTTPUnsupportedMediaType (415)
#   - Gem::Net::HTTPRequestedRangeNotSatisfiable (416)
#   - Gem::Net::HTTPExpectationFailed (417)
#   - Gem::Net::HTTPMisdirectedRequest (421)
#   - Gem::Net::HTTPUnprocessableEntity (422)
#   - Gem::Net::HTTPLocked (423)
#   - Gem::Net::HTTPFailedDependency (424)
#   - Gem::Net::HTTPUpgradeRequired (426)
#   - Gem::Net::HTTPPreconditionRequired (428)
#   - Gem::Net::HTTPTooManyRequests (429)
#   - Gem::Net::HTTPRequestHeaderFieldsTooLarge (431)
#   - Gem::Net::HTTPUnavailableForLegalReasons (451)
#
# - Gem::Net::HTTPServerError:
#
#   - Gem::Net::HTTPInternalServerError (500)
#   - Gem::Net::HTTPNotImplemented (501)
#   - Gem::Net::HTTPBadGateway (502)
#   - Gem::Net::HTTPServiceUnavailable (503)
#   - Gem::Net::HTTPGatewayTimeOut (504)
#   - Gem::Net::HTTPVersionNotSupported (505)
#   - Gem::Net::HTTPVariantAlsoNegotiates (506)
#   - Gem::Net::HTTPInsufficientStorage (507)
#   - Gem::Net::HTTPLoopDetected (508)
#   - Gem::Net::HTTPNotExtended (510)
#   - Gem::Net::HTTPNetworkAuthenticationRequired (511)
#
# There is also the Gem::Net::HTTPBadResponse exception which is raised when
# there is a protocol error.
#
class Gem::Net::HTTPResponse
  class << self
    # true if the response has a body.
    def body_permitted?
      self::HAS_BODY
    end

    def exception_type   # :nodoc: internal use only
      self::EXCEPTION_TYPE
    end

    def read_new(sock)   #:nodoc: internal use only
      httpv, code, msg = read_status_line(sock)
      res = response_class(code).new(httpv, code, msg)
      each_response_header(sock) do |k,v|
        res.add_field k, v
      end
      res
    end

    private

    def read_status_line(sock)
      str = sock.readline
      m = /\AHTTP(?:\/(\d+\.\d+))?\s+(\d\d\d)(?:\s+(.*))?\z/in.match(str) or
        raise Gem::Net::HTTPBadResponse, "wrong status line: #{str.dump}"
      m.captures
    end

    def response_class(code)
      CODE_TO_OBJ[code] or
      CODE_CLASS_TO_OBJ[code[0,1]] or
      Gem::Net::HTTPUnknownResponse
    end

    def each_response_header(sock)
      key = value = nil
      while true
        line = sock.readuntil("\n", true).sub(/\s+\z/, '')
        break if line.empty?
        if line[0] == ?\s or line[0] == ?\t and value
          value << ' ' unless value.empty?
          value << line.strip
        else
          yield key, value if key
          key, value = line.strip.split(/\s*:\s*/, 2)
          raise Gem::Net::HTTPBadResponse, 'wrong header line format' if value.nil?
        end
      end
      yield key, value if key
    end
  end

  # next is to fix bug in RDoc, where the private inside class << self
  # spills out.
  public

  include Gem::Net::HTTPHeader

  def initialize(httpv, code, msg)   #:nodoc: internal use only
    @http_version = httpv
    @code         = code
    @message      = msg
    initialize_http_header nil
    @body = nil
    @read = false
    @uri  = nil
    @decode_content = false
    @body_encoding = false
    @ignore_eof = true
  end

  # The HTTP version supported by the server.
  attr_reader :http_version

  # The HTTP result code string. For example, '302'.  You can also
  # determine the response type by examining which response subclass
  # the response object is an instance of.
  attr_reader :code

  # The HTTP result message sent by the server. For example, 'Not Found'.
  attr_reader :message
  alias msg message   # :nodoc: obsolete

  # The Gem::URI used to fetch this response.  The response Gem::URI is only available
  # if a Gem::URI was used to create the request.
  attr_reader :uri

  # Set to true automatically when the request did not contain an
  # Accept-Encoding header from the user.
  attr_accessor :decode_content

  # Returns the value set by body_encoding=, or +false+ if none;
  # see #body_encoding=.
  attr_reader :body_encoding

  # Sets the encoding that should be used when reading the body:
  #
  # - If the given value is an Encoding object, that encoding will be used.
  # - Otherwise if the value is a string, the value of
  #   {Encoding#find(value)}[https://docs.ruby-lang.org/en/master/Encoding.html#method-c-find]
  #   will be used.
  # - Otherwise an encoding will be deduced from the body itself.
  #
  # Examples:
  #
  #   http = Gem::Net::HTTP.new(hostname)
  #   req = Gem::Net::HTTP::Get.new('/')
  #
  #   http.request(req) do |res|
  #     p res.body.encoding # => #<Encoding:ASCII-8BIT>
  #   end
  #
  #   http.request(req) do |res|
  #     res.body_encoding = "UTF-8"
  #     p res.body.encoding # => #<Encoding:UTF-8>
  #   end
  #
  def body_encoding=(value)
    value = Encoding.find(value) if value.is_a?(String)
    @body_encoding = value
  end

  # Whether to ignore EOF when reading bodies with a specified Content-Length
  # header.
  attr_accessor :ignore_eof

  def inspect
    "#<#{self.class} #{@code} #{@message} readbody=#{@read}>"
  end

  #
  # response <-> exception relationship
  #

  def code_type   #:nodoc:
    self.class
  end

  def error!   #:nodoc:
    message = @code
    message = "#{message} #{@message.dump}" if @message
    raise error_type().new(message, self)
  end

  def error_type   #:nodoc:
    self.class::EXCEPTION_TYPE
  end

  # Raises an HTTP error if the response is not 2xx (success).
  def value
    error! unless self.kind_of?(Gem::Net::HTTPSuccess)
  end

  def uri= uri # :nodoc:
    @uri = uri.dup if uri
  end

  #
  # header (for backward compatibility only; DO NOT USE)
  #

  def response   #:nodoc:
    warn "Gem::Net::HTTPResponse#response is obsolete", uplevel: 1 if $VERBOSE
    self
  end

  def header   #:nodoc:
    warn "Gem::Net::HTTPResponse#header is obsolete", uplevel: 1 if $VERBOSE
    self
  end

  def read_header   #:nodoc:
    warn "Gem::Net::HTTPResponse#read_header is obsolete", uplevel: 1 if $VERBOSE
    self
  end

  #
  # body
  #

  def reading_body(sock, reqmethodallowbody)  #:nodoc: internal use only
    @socket = sock
    @body_exist = reqmethodallowbody && self.class.body_permitted?
    begin
      yield
      self.body   # ensure to read body
    ensure
      @socket = nil
    end
  end

  # Gets the entity body returned by the remote HTTP server.
  #
  # If a block is given, the body is passed to the block, and
  # the body is provided in fragments, as it is read in from the socket.
  #
  # If +dest+ argument is given, response is read into that variable,
  # with <code>dest#<<</code> method (it could be String or IO, or any
  # other object responding to <code><<</code>).
  #
  # Calling this method a second or subsequent time for the same
  # HTTPResponse object will return the value already read.
  #
  #   http.request_get('/index.html') {|res|
  #     puts res.read_body
  #   }
  #
  #   http.request_get('/index.html') {|res|
  #     p res.read_body.object_id   # 538149362
  #     p res.read_body.object_id   # 538149362
  #   }
  #
  #   # using iterator
  #   http.request_get('/index.html') {|res|
  #     res.read_body do |segment|
  #       print segment
  #     end
  #   }
  #
  def read_body(dest = nil, &block)
    if @read
      raise IOError, "#{self.class}\#read_body called twice" if dest or block
      return @body
    end
    to = procdest(dest, block)
    stream_check
    if @body_exist
      read_body_0 to
      @body = to
    else
      @body = nil
    end
    @read = true
    return if @body.nil?

    case enc = @body_encoding
    when Encoding, false, nil
      # Encoding: force given encoding
      # false/nil: do not force encoding
    else
      # other value: detect encoding from body
      enc = detect_encoding(@body)
    end

    @body.force_encoding(enc) if enc

    @body
  end

  # Returns the string response body;
  # note that repeated calls for the unmodified body return a cached string:
  #
  #   path = '/todos/1'
  #   Gem::Net::HTTP.start(hostname) do |http|
  #     res = http.get(path)
  #     p res.body
  #     p http.head(path).body # No body.
  #   end
  #
  # Output:
  #
  #   "{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false\n}"
  #   nil
  #
  def body
    read_body()
  end

  # Sets the body of the response to the given value.
  def body=(value)
    @body = value
  end

  alias entity body   #:nodoc: obsolete

  private

  # :nodoc:
  def detect_encoding(str, encoding=nil)
    if encoding
    elsif encoding = type_params['charset']
    elsif encoding = check_bom(str)
    else
      encoding = case content_type&.downcase
      when %r{text/x(?:ht)?ml|application/(?:[^+]+\+)?xml}
        /\A<xml[ \t\r\n]+
          version[ \t\r\n]*=[ \t\r\n]*(?:"[0-9.]+"|'[0-9.]*')[ \t\r\n]+
          encoding[ \t\r\n]*=[ \t\r\n]*
          (?:"([A-Za-z][\-A-Za-z0-9._]*)"|'([A-Za-z][\-A-Za-z0-9._]*)')/x =~ str
        encoding = $1 || $2 || Encoding::UTF_8
      when %r{text/html.*}
        sniff_encoding(str)
      end
    end
    return encoding
  end

  # :nodoc:
  def sniff_encoding(str, encoding=nil)
    # the encoding sniffing algorithm
    # http://www.w3.org/TR/html5/parsing.html#determining-the-character-encoding
    if enc = scanning_meta(str)
      enc
    # 6. last visited page or something
    # 7. frequency
    elsif str.ascii_only?
      Encoding::US_ASCII
    elsif str.dup.force_encoding(Encoding::UTF_8).valid_encoding?
      Encoding::UTF_8
    end
    # 8. implementation-defined or user-specified
  end

  # :nodoc:
  def check_bom(str)
    case str.byteslice(0, 2)
    when "\xFE\xFF"
      return Encoding::UTF_16BE
    when "\xFF\xFE"
      return Encoding::UTF_16LE
    end
    if "\xEF\xBB\xBF" == str.byteslice(0, 3)
      return Encoding::UTF_8
    end
    nil
  end

  # :nodoc:
  def scanning_meta(str)
    require 'strscan'
    ss = StringScanner.new(str)
    if ss.scan_until(/<meta[\t\n\f\r ]*/)
      attrs = {} # attribute_list
      got_pragma = false
      need_pragma = nil
      charset = nil

      # step: Attributes
      while attr = get_attribute(ss)
        name, value = *attr
        next if attrs[name]
        attrs[name] = true
        case name
        when 'http-equiv'
          got_pragma = true if value == 'content-type'
        when 'content'
          encoding = extracting_encodings_from_meta_elements(value)
          unless charset
            charset = encoding
          end
          need_pragma = true
        when 'charset'
          need_pragma = false
          charset = value
        end
      end

      # step: Processing
      return if need_pragma.nil?
      return if need_pragma && !got_pragma

      charset = Encoding.find(charset) rescue nil
      return unless charset
      charset = Encoding::UTF_8 if charset == Encoding::UTF_16
      return charset # tentative
    end
    nil
  end

  def get_attribute(ss)
    ss.scan(/[\t\n\f\r \/]*/)
    if ss.peek(1) == '>'
      ss.getch
      return nil
    end
    name = ss.scan(/[^=\t\n\f\r \/>]*/)
    name.downcase!
    raise if name.empty?
    ss.skip(/[\t\n\f\r ]*/)
    if ss.getch != '='
      value = ''
      return [name, value]
    end
    ss.skip(/[\t\n\f\r ]*/)
    case ss.peek(1)
    when '"'
      ss.getch
      value = ss.scan(/[^"]+/)
      value.downcase!
      ss.getch
    when "'"
      ss.getch
      value = ss.scan(/[^']+/)
      value.downcase!
      ss.getch
    when '>'
      value = ''
    else
      value = ss.scan(/[^\t\n\f\r >]+/)
      value.downcase!
    end
    [name, value]
  end

  def extracting_encodings_from_meta_elements(value)
    # http://dev.w3.org/html5/spec/fetching-resources.html#algorithm-for-extracting-an-encoding-from-a-meta-element
    if /charset[\t\n\f\r ]*=(?:"([^"]*)"|'([^']*)'|["']|\z|([^\t\n\f\r ;]+))/i =~ value
      return $1 || $2 || $3
    end
    return nil
  end

  ##
  # Checks for a supported Content-Encoding header and yields an Inflate
  # wrapper for this response's socket when zlib is present.  If the
  # Content-Encoding is not supported or zlib is missing, the plain socket is
  # yielded.
  #
  # If a Content-Range header is present, a plain socket is yielded as the
  # bytes in the range may not be a complete deflate block.

  def inflater # :nodoc:
    return yield @socket unless Gem::Net::HTTP::HAVE_ZLIB
    return yield @socket unless @decode_content
    return yield @socket if self['content-range']

    v = self['content-encoding']
    case v&.downcase
    when 'deflate', 'gzip', 'x-gzip' then
      self.delete 'content-encoding'

      inflate_body_io = Inflater.new(@socket)

      begin
        yield inflate_body_io
        success = true
      ensure
        begin
          inflate_body_io.finish
          if self['content-length']
            self['content-length'] = inflate_body_io.bytes_inflated.to_s
          end
        rescue => err
          # Ignore #finish's error if there is an exception from yield
          raise err if success
        end
      end
    when 'none', 'identity' then
      self.delete 'content-encoding'

      yield @socket
    else
      yield @socket
    end
  end

  def read_body_0(dest)
    inflater do |inflate_body_io|
      if chunked?
        read_chunked dest, inflate_body_io
        return
      end

      @socket = inflate_body_io

      clen = content_length()
      if clen
        @socket.read clen, dest, @ignore_eof
        return
      end
      clen = range_length()
      if clen
        @socket.read clen, dest
        return
      end
      @socket.read_all dest
    end
  end

  ##
  # read_chunked reads from +@socket+ for chunk-size, chunk-extension, CRLF,
  # etc. and +chunk_data_io+ for chunk-data which may be deflate or gzip
  # encoded.
  #
  # See RFC 2616 section 3.6.1 for definitions

  def read_chunked(dest, chunk_data_io) # :nodoc:
    total = 0
    while true
      line = @socket.readline
      hexlen = line.slice(/[0-9a-fA-F]+/) or
          raise Gem::Net::HTTPBadResponse, "wrong chunk size line: #{line}"
      len = hexlen.hex
      break if len == 0
      begin
        chunk_data_io.read len, dest
      ensure
        total += len
        @socket.read 2   # \r\n
      end
    end
    until @socket.readline.empty?
      # none
    end
  end

  def stream_check
    raise IOError, 'attempt to read body out of block' if @socket.nil? || @socket.closed?
  end

  def procdest(dest, block)
    raise ArgumentError, 'both arg and block given for HTTP method' if
      dest and block
    if block
      Gem::Net::ReadAdapter.new(block)
    else
      dest || +''
    end
  end

  ##
  # Inflater is a wrapper around Gem::Net::BufferedIO that transparently inflates
  # zlib and gzip streams.

  class Inflater # :nodoc:

    ##
    # Creates a new Inflater wrapping +socket+

    def initialize socket
      @socket = socket
      # zlib with automatic gzip detection
      @inflate = Zlib::Inflate.new(32 + Zlib::MAX_WBITS)
    end

    ##
    # Finishes the inflate stream.

    def finish
      return if @inflate.total_in == 0
      @inflate.finish
    end

    ##
    # The number of bytes inflated, used to update the Content-Length of
    # the response.

    def bytes_inflated
      @inflate.total_out
    end

    ##
    # Returns a Gem::Net::ReadAdapter that inflates each read chunk into +dest+.
    #
    # This allows a large response body to be inflated without storing the
    # entire body in memory.

    def inflate_adapter(dest)
      if dest.respond_to?(:set_encoding)
        dest.set_encoding(Encoding::ASCII_8BIT)
      elsif dest.respond_to?(:force_encoding)
        dest.force_encoding(Encoding::ASCII_8BIT)
      end
      block = proc do |compressed_chunk|
        @inflate.inflate(compressed_chunk) do |chunk|
          compressed_chunk.clear
          dest << chunk
        end
      end

      Gem::Net::ReadAdapter.new(block)
    end

    ##
    # Reads +clen+ bytes from the socket, inflates them, then writes them to
    # +dest+.  +ignore_eof+ is passed down to Gem::Net::BufferedIO#read
    #
    # Unlike Gem::Net::BufferedIO#read, this method returns more than +clen+ bytes.
    # At this time there is no way for a user of Gem::Net::HTTPResponse to read a
    # specific number of bytes from the HTTP response body, so this internal
    # API does not return the same number of bytes as were requested.
    #
    # See https://bugs.ruby-lang.org/issues/6492 for further discussion.

    def read clen, dest, ignore_eof = false
      temp_dest = inflate_adapter(dest)

      @socket.read clen, temp_dest, ignore_eof
    end

    ##
    # Reads the rest of the socket, inflates it, then writes it to +dest+.

    def read_all dest
      temp_dest = inflate_adapter(dest)

      @socket.read_all temp_dest
    end

  end

end

