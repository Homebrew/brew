# frozen_string_literal: false
# HTTP response class.
#
# This class wraps together the response header and the response body (the
# entity requested).
#
# It mixes in the HTTPHeader module, which provides access to response
# header values both via hash-like methods and via individual readers.
#
# Note that each possible HTTP response code defines its own
# HTTPResponse subclass. All classes are defined under the Net module.
# Indentation indicates inheritance.  For a list of the classes see Net::HTTP.
#
# Correspondence <code>HTTP code => class</code> is stored in CODE_TO_OBJ
# constant:
#
#    Net::HTTPResponse::CODE_TO_OBJ['404'] #=> Net::HTTPNotFound
#
class Net::HTTPResponse
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
        raise Net::HTTPBadResponse, "wrong status line: #{str.dump}"
      m.captures
    end

    def response_class(code)
      CODE_TO_OBJ[code] or
      CODE_CLASS_TO_OBJ[code[0,1]] or
      Net::HTTPUnknownResponse
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
          raise Net::HTTPBadResponse, 'wrong header line format' if value.nil?
        end
      end
      yield key, value if key
    end
  end

  # next is to fix bug in RDoc, where the private inside class << self
  # spills out.
  public

  include Net::HTTPHeader

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

  # The URI used to fetch this response.  The response URI is only available
  # if a URI was used to create the request.
  attr_reader :uri

  # Set to true automatically when the request did not contain an
  # Accept-Encoding header from the user.
  attr_accessor :decode_content

  # The encoding to use for the response body. If Encoding, use that encoding.
  # If other true value, attempt to detect the appropriate encoding, and use
  # that.
  attr_reader :body_encoding

  # Set the encoding to use for the response body.  If given a String, find
  # the related Encoding.
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
    message += ' ' + @message.dump if @message
    raise error_type().new(message, self)
  end

  def error_type   #:nodoc:
    self.class::EXCEPTION_TYPE
  end

  # Raises an HTTP error if the response is not 2xx (success).
  def value
    error! unless self.kind_of?(Net::HTTPSuccess)
  end

  def uri= uri # :nodoc:
    @uri = uri.dup if uri
  end

  #
  # header (for backward compatibility only; DO NOT USE)
  #

  def response   #:nodoc:
    warn "Net::HTTPResponse#response is obsolete", uplevel: 1 if $VERBOSE
    self
  end

  def header   #:nodoc:
    warn "Net::HTTPResponse#header is obsolete", uplevel: 1 if $VERBOSE
    self
  end

  def read_header   #:nodoc:
    warn "Net::HTTPResponse#read_header is obsolete", uplevel: 1 if $VERBOSE
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

  # Returns the full entity body.
  #
  # Calling this method a second or subsequent time will return the
  # string already read.
  #
  #   http.request_get('/index.html') {|res|
  #     puts res.body
  #   }
  #
  #   http.request_get('/index.html') {|res|
  #     p res.body.object_id   # 538149362
  #     p res.body.object_id   # 538149362
  #   }
  #
  def body
    read_body()
  end

  # Because it may be necessary to modify the body, Eg, decompression
  # this method facilitates that.
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
    return yield @socket unless Net::HTTP::HAVE_ZLIB
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
          raise Net::HTTPBadResponse, "wrong chunk size line: #{line}"
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
    raise IOError, 'attempt to read body out of block' if @socket.closed?
  end

  def procdest(dest, block)
    raise ArgumentError, 'both arg and block given for HTTP method' if
      dest and block
    if block
      Net::ReadAdapter.new(block)
    else
      dest || ''
    end
  end

  ##
  # Inflater is a wrapper around Net::BufferedIO that transparently inflates
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
    # Returns a Net::ReadAdapter that inflates each read chunk into +dest+.
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

      Net::ReadAdapter.new(block)
    end

    ##
    # Reads +clen+ bytes from the socket, inflates them, then writes them to
    # +dest+.  +ignore_eof+ is passed down to Net::BufferedIO#read
    #
    # Unlike Net::BufferedIO#read, this method returns more than +clen+ bytes.
    # At this time there is no way for a user of Net::HTTPResponse to read a
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

