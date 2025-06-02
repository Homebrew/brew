# frozen_string_literal: false
# HTTPGenericRequest is the parent of the Net::HTTPRequest class.
# Do not use this directly; use a subclass of Net::HTTPRequest.
#
# Mixes in the Net::HTTPHeader module to provide easier access to HTTP headers.
#
class Net::HTTPGenericRequest

  include Net::HTTPHeader

  def initialize(m, reqbody, resbody, uri_or_path, initheader = nil)
    @method = m
    @request_has_body = reqbody
    @response_has_body = resbody

    if URI === uri_or_path then
      raise ArgumentError, "not an HTTP URI" unless URI::HTTP === uri_or_path
      hostname = uri_or_path.hostname
      raise ArgumentError, "no host component for URI" unless (hostname && hostname.length > 0)
      @uri = uri_or_path.dup
      host = @uri.hostname.dup
      host << ":".freeze << @uri.port.to_s if @uri.port != @uri.default_port
      @path = uri_or_path.request_uri
      raise ArgumentError, "no HTTP request path given" unless @path
    else
      @uri = nil
      host = nil
      raise ArgumentError, "no HTTP request path given" unless uri_or_path
      raise ArgumentError, "HTTP request path is empty" if uri_or_path.empty?
      @path = uri_or_path.dup
    end

    @decode_content = false

    if Net::HTTP::HAVE_ZLIB then
      if !initheader ||
         !initheader.keys.any? { |k|
           %w[accept-encoding range].include? k.downcase
         } then
        @decode_content = true if @response_has_body
        initheader = initheader ? initheader.dup : {}
        initheader["accept-encoding"] =
          "gzip;q=1.0,deflate;q=0.6,identity;q=0.3"
      end
    end

    initialize_http_header initheader
    self['Accept'] ||= '*/*'
    self['User-Agent'] ||= 'Ruby'
    self['Host'] ||= host if host
    @body = nil
    @body_stream = nil
    @body_data = nil
  end

  attr_reader :method
  attr_reader :path
  attr_reader :uri

  # Automatically set to false if the user sets the Accept-Encoding header.
  # This indicates they wish to handle Content-encoding in responses
  # themselves.
  attr_reader :decode_content

  def inspect
    "\#<#{self.class} #{@method}>"
  end

  ##
  # Don't automatically decode response content-encoding if the user indicates
  # they want to handle it.

  def []=(key, val) # :nodoc:
    @decode_content = false if key.downcase == 'accept-encoding'

    super key, val
  end

  def request_body_permitted?
    @request_has_body
  end

  def response_body_permitted?
    @response_has_body
  end

  def body_exist?
    warn "Net::HTTPRequest#body_exist? is obsolete; use response_body_permitted?", uplevel: 1 if $VERBOSE
    response_body_permitted?
  end

  attr_reader :body

  def body=(str)
    @body = str
    @body_stream = nil
    @body_data = nil
    str
  end

  attr_reader :body_stream

  def body_stream=(input)
    @body = nil
    @body_stream = input
    @body_data = nil
    input
  end

  def set_body_internal(str)   #:nodoc: internal use only
    raise ArgumentError, "both of body argument and HTTPRequest#body set" if str and (@body or @body_stream)
    self.body = str if str
    if @body.nil? && @body_stream.nil? && @body_data.nil? && request_body_permitted?
      self.body = ''
    end
  end

  #
  # write
  #

  def exec(sock, ver, path)   #:nodoc: internal use only
    if @body
      send_request_with_body sock, ver, path, @body
    elsif @body_stream
      send_request_with_body_stream sock, ver, path, @body_stream
    elsif @body_data
      send_request_with_body_data sock, ver, path, @body_data
    else
      write_header sock, ver, path
    end
  end

  def update_uri(addr, port, ssl) # :nodoc: internal use only
    # reflect the connection and @path to @uri
    return unless @uri

    if ssl
      scheme = 'https'.freeze
      klass = URI::HTTPS
    else
      scheme = 'http'.freeze
      klass = URI::HTTP
    end

    if host = self['host']
      host.sub!(/:.*/m, ''.freeze)
    elsif host = @uri.host
    else
     host = addr
    end
    # convert the class of the URI
    if @uri.is_a?(klass)
      @uri.host = host
      @uri.port = port
    else
      @uri = klass.new(
        scheme, @uri.userinfo,
        host, port, nil,
        @uri.path, nil, @uri.query, nil)
    end
  end

  private

  class Chunker #:nodoc:
    def initialize(sock)
      @sock = sock
      @prev = nil
    end

    def write(buf)
      # avoid memcpy() of buf, buf can huge and eat memory bandwidth
      rv = buf.bytesize
      @sock.write("#{rv.to_s(16)}\r\n", buf, "\r\n")
      rv
    end

    def finish
      @sock.write("0\r\n\r\n")
    end
  end

  def send_request_with_body(sock, ver, path, body)
    self.content_length = body.bytesize
    delete 'Transfer-Encoding'
    supply_default_content_type
    write_header sock, ver, path
    wait_for_continue sock, ver if sock.continue_timeout
    sock.write body
  end

  def send_request_with_body_stream(sock, ver, path, f)
    unless content_length() or chunked?
      raise ArgumentError,
          "Content-Length not given and Transfer-Encoding is not `chunked'"
    end
    supply_default_content_type
    write_header sock, ver, path
    wait_for_continue sock, ver if sock.continue_timeout
    if chunked?
      chunker = Chunker.new(sock)
      IO.copy_stream(f, chunker)
      chunker.finish
    else
      IO.copy_stream(f, sock)
    end
  end

  def send_request_with_body_data(sock, ver, path, params)
    if /\Amultipart\/form-data\z/i !~ self.content_type
      self.content_type = 'application/x-www-form-urlencoded'
      return send_request_with_body(sock, ver, path, URI.encode_www_form(params))
    end

    opt = @form_option.dup
    require 'securerandom' unless defined?(SecureRandom)
    opt[:boundary] ||= SecureRandom.urlsafe_base64(40)
    self.set_content_type(self.content_type, boundary: opt[:boundary])
    if chunked?
      write_header sock, ver, path
      encode_multipart_form_data(sock, params, opt)
    else
      require 'tempfile'
      file = Tempfile.new('multipart')
      file.binmode
      encode_multipart_form_data(file, params, opt)
      file.rewind
      self.content_length = file.size
      write_header sock, ver, path
      IO.copy_stream(file, sock)
      file.close(true)
    end
  end

  def encode_multipart_form_data(out, params, opt)
    charset = opt[:charset]
    boundary = opt[:boundary]
    require 'securerandom' unless defined?(SecureRandom)
    boundary ||= SecureRandom.urlsafe_base64(40)
    chunked_p = chunked?

    buf = ''
    params.each do |key, value, h={}|
      key = quote_string(key, charset)
      filename =
        h.key?(:filename) ? h[:filename] :
        value.respond_to?(:to_path) ? File.basename(value.to_path) :
        nil

      buf << "--#{boundary}\r\n"
      if filename
        filename = quote_string(filename, charset)
        type = h[:content_type] || 'application/octet-stream'
        buf << "Content-Disposition: form-data; " \
          "name=\"#{key}\"; filename=\"#{filename}\"\r\n" \
          "Content-Type: #{type}\r\n\r\n"
        if !out.respond_to?(:write) || !value.respond_to?(:read)
          # if +out+ is not an IO or +value+ is not an IO
          buf << (value.respond_to?(:read) ? value.read : value)
        elsif value.respond_to?(:size) && chunked_p
          # if +out+ is an IO and +value+ is a File, use IO.copy_stream
          flush_buffer(out, buf, chunked_p)
          out << "%x\r\n" % value.size if chunked_p
          IO.copy_stream(value, out)
          out << "\r\n" if chunked_p
        else
          # +out+ is an IO, and +value+ is not a File but an IO
          flush_buffer(out, buf, chunked_p)
          1 while flush_buffer(out, value.read(4096), chunked_p)
        end
      else
        # non-file field:
        #   HTML5 says, "The parts of the generated multipart/form-data
        #   resource that correspond to non-file fields must not have a
        #   Content-Type header specified."
        buf << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
        buf << (value.respond_to?(:read) ? value.read : value)
      end
      buf << "\r\n"
    end
    buf << "--#{boundary}--\r\n"
    flush_buffer(out, buf, chunked_p)
    out << "0\r\n\r\n" if chunked_p
  end

  def quote_string(str, charset)
    str = str.encode(charset, fallback:->(c){'&#%d;'%c.encode("UTF-8").ord}) if charset
    str.gsub(/[\\"]/, '\\\\\&')
  end

  def flush_buffer(out, buf, chunked_p)
    return unless buf
    out << "%x\r\n"%buf.bytesize if chunked_p
    out << buf
    out << "\r\n" if chunked_p
    buf.clear
  end

  def supply_default_content_type
    return if content_type()
    warn 'net/http: Content-Type did not set; using application/x-www-form-urlencoded', uplevel: 1 if $VERBOSE
    set_content_type 'application/x-www-form-urlencoded'
  end

  ##
  # Waits up to the continue timeout for a response from the server provided
  # we're speaking HTTP 1.1 and are expecting a 100-continue response.

  def wait_for_continue(sock, ver)
    if ver >= '1.1' and @header['expect'] and
        @header['expect'].include?('100-continue')
      if sock.io.to_io.wait_readable(sock.continue_timeout)
        res = Net::HTTPResponse.read_new(sock)
        unless res.kind_of?(Net::HTTPContinue)
          res.decode_content = @decode_content
          throw :response, res
        end
      end
    end
  end

  def write_header(sock, ver, path)
    reqline = "#{@method} #{path} HTTP/#{ver}"
    if /[\r\n]/ =~ reqline
      raise ArgumentError, "A Request-Line must not contain CR or LF"
    end
    buf = ""
    buf << reqline << "\r\n"
    each_capitalized do |k,v|
      buf << "#{k}: #{v}\r\n"
    end
    buf << "\r\n"
    sock.write buf
  end

end

