# frozen_string_literal: true
#--
# Methods for generating HTML, parsing CGI-related parameters, and
# generating HTTP responses.
#++
class CGI
  unless const_defined?(:Util)
    module Util
      @@accept_charset = "UTF-8" # :nodoc:
    end
    include Util
    extend Util
  end

  $CGI_ENV = ENV    # for FCGI support

  # String for carriage return
  CR  = "\015"

  # String for linefeed
  LF  = "\012"

  # Standard internet newline sequence
  EOL = CR + LF

  REVISION = '$Id$' #:nodoc:

  # Whether processing will be required in binary vs text
  NEEDS_BINMODE = File::BINARY != 0

  # Path separators in different environments.
  PATH_SEPARATOR = {'UNIX'=>'/', 'WINDOWS'=>'\\', 'MACINTOSH'=>':'}

  # HTTP status codes.
  HTTP_STATUS = {
    "OK"                  => "200 OK",
    "PARTIAL_CONTENT"     => "206 Partial Content",
    "MULTIPLE_CHOICES"    => "300 Multiple Choices",
    "MOVED"               => "301 Moved Permanently",
    "REDIRECT"            => "302 Found",
    "NOT_MODIFIED"        => "304 Not Modified",
    "BAD_REQUEST"         => "400 Bad Request",
    "AUTH_REQUIRED"       => "401 Authorization Required",
    "FORBIDDEN"           => "403 Forbidden",
    "NOT_FOUND"           => "404 Not Found",
    "METHOD_NOT_ALLOWED"  => "405 Method Not Allowed",
    "NOT_ACCEPTABLE"      => "406 Not Acceptable",
    "LENGTH_REQUIRED"     => "411 Length Required",
    "PRECONDITION_FAILED" => "412 Precondition Failed",
    "SERVER_ERROR"        => "500 Internal Server Error",
    "NOT_IMPLEMENTED"     => "501 Method Not Implemented",
    "BAD_GATEWAY"         => "502 Bad Gateway",
    "VARIANT_ALSO_VARIES" => "506 Variant Also Negotiates"
  }

  # :startdoc:

  # Synonym for ENV.
  def env_table
    ENV
  end

  # Synonym for $stdin.
  def stdinput
    $stdin
  end

  # Synonym for $stdout.
  def stdoutput
    $stdout
  end

  private :env_table, :stdinput, :stdoutput

  # Create an HTTP header block as a string.
  #
  # :call-seq:
  #   http_header(content_type_string="text/html")
  #   http_header(headers_hash)
  #
  # Includes the empty line that ends the header block.
  #
  # +content_type_string+::
  #   If this form is used, this string is the <tt>Content-Type</tt>
  # +headers_hash+::
  #   A Hash of header values. The following header keys are recognized:
  #
  #   type:: The Content-Type header.  Defaults to "text/html"
  #   charset:: The charset of the body, appended to the Content-Type header.
  #   nph:: A boolean value.  If true, prepend protocol string and status
  #         code, and date; and sets default values for "server" and
  #         "connection" if not explicitly set.
  #   status::
  #     The HTTP status code as a String, returned as the Status header.  The
  #     values are:
  #
  #     OK:: 200 OK
  #     PARTIAL_CONTENT:: 206 Partial Content
  #     MULTIPLE_CHOICES:: 300 Multiple Choices
  #     MOVED:: 301 Moved Permanently
  #     REDIRECT:: 302 Found
  #     NOT_MODIFIED:: 304 Not Modified
  #     BAD_REQUEST:: 400 Bad Request
  #     AUTH_REQUIRED:: 401 Authorization Required
  #     FORBIDDEN:: 403 Forbidden
  #     NOT_FOUND:: 404 Not Found
  #     METHOD_NOT_ALLOWED:: 405 Method Not Allowed
  #     NOT_ACCEPTABLE:: 406 Not Acceptable
  #     LENGTH_REQUIRED:: 411 Length Required
  #     PRECONDITION_FAILED:: 412 Precondition Failed
  #     SERVER_ERROR:: 500 Internal Server Error
  #     NOT_IMPLEMENTED:: 501 Method Not Implemented
  #     BAD_GATEWAY:: 502 Bad Gateway
  #     VARIANT_ALSO_VARIES:: 506 Variant Also Negotiates
  #
  #   server:: The server software, returned as the Server header.
  #   connection:: The connection type, returned as the Connection header (for
  #                instance, "close".
  #   length:: The length of the content that will be sent, returned as the
  #            Content-Length header.
  #   language:: The language of the content, returned as the Content-Language
  #              header.
  #   expires:: The time on which the current content expires, as a +Time+
  #             object, returned as the Expires header.
  #   cookie::
  #     A cookie or cookies, returned as one or more Set-Cookie headers.  The
  #     value can be the literal string of the cookie; a CGI::Cookie object;
  #     an Array of literal cookie strings or Cookie objects; or a hash all of
  #     whose values are literal cookie strings or Cookie objects.
  #
  #     These cookies are in addition to the cookies held in the
  #     @output_cookies field.
  #
  #   Other headers can also be set; they are appended as key: value.
  #
  # Examples:
  #
  #   http_header
  #     # Content-Type: text/html
  #
  #   http_header("text/plain")
  #     # Content-Type: text/plain
  #
  #   http_header("nph"        => true,
  #               "status"     => "OK",  # == "200 OK"
  #                 # "status"     => "200 GOOD",
  #               "server"     => ENV['SERVER_SOFTWARE'],
  #               "connection" => "close",
  #               "type"       => "text/html",
  #               "charset"    => "iso-2022-jp",
  #                 # Content-Type: text/html; charset=iso-2022-jp
  #               "length"     => 103,
  #               "language"   => "ja",
  #               "expires"    => Time.now + 30,
  #               "cookie"     => [cookie1, cookie2],
  #               "my_header1" => "my_value",
  #               "my_header2" => "my_value")
  #
  # This method does not perform charset conversion.
  def http_header(options='text/html')
    if options.is_a?(String)
      content_type = options
      buf = _header_for_string(content_type)
    elsif options.is_a?(Hash)
      if options.size == 1 && options.has_key?('type')
        content_type = options['type']
        buf = _header_for_string(content_type)
      else
        buf = _header_for_hash(options.dup)
      end
    else
      raise ArgumentError.new("expected String or Hash but got #{options.class}")
    end
    if defined?(MOD_RUBY)
      _header_for_modruby(buf)
      return ''
    else
      buf << EOL    # empty line of separator
      return buf
    end
  end # http_header()

  # This method is an alias for #http_header, when HTML5 tag maker is inactive.
  #
  # NOTE: use #http_header to create HTTP header blocks, this alias is only
  # provided for backwards compatibility.
  #
  # Using #header with the HTML5 tag maker will create a <header> element.
  alias :header :http_header

  def _no_crlf_check(str)
    if str
      str = str.to_s
      raise "A HTTP status or header field must not include CR and LF" if str =~ /[\r\n]/
      str
    else
      nil
    end
  end
  private :_no_crlf_check

  def _header_for_string(content_type) #:nodoc:
    buf = ''.dup
    if nph?()
      buf << "#{_no_crlf_check($CGI_ENV['SERVER_PROTOCOL']) || 'HTTP/1.0'} 200 OK#{EOL}"
      buf << "Date: #{CGI.rfc1123_date(Time.now)}#{EOL}"
      buf << "Server: #{_no_crlf_check($CGI_ENV['SERVER_SOFTWARE'])}#{EOL}"
      buf << "Connection: close#{EOL}"
    end
    buf << "Content-Type: #{_no_crlf_check(content_type)}#{EOL}"
    if @output_cookies
      @output_cookies.each {|cookie| buf << "Set-Cookie: #{_no_crlf_check(cookie)}#{EOL}" }
    end
    return buf
  end # _header_for_string
  private :_header_for_string

  def _header_for_hash(options)  #:nodoc:
    buf = ''.dup
    ## add charset to option['type']
    options['type'] ||= 'text/html'
    charset = options.delete('charset')
    options['type'] += "; charset=#{charset}" if charset
    ## NPH
    options.delete('nph') if defined?(MOD_RUBY)
    if options.delete('nph') || nph?()
      protocol = _no_crlf_check($CGI_ENV['SERVER_PROTOCOL']) || 'HTTP/1.0'
      status = options.delete('status')
      status = HTTP_STATUS[status] || _no_crlf_check(status) || '200 OK'
      buf << "#{protocol} #{status}#{EOL}"
      buf << "Date: #{CGI.rfc1123_date(Time.now)}#{EOL}"
      options['server'] ||= $CGI_ENV['SERVER_SOFTWARE'] || ''
      options['connection'] ||= 'close'
    end
    ## common headers
    status = options.delete('status')
    buf << "Status: #{HTTP_STATUS[status] || _no_crlf_check(status)}#{EOL}" if status
    server = options.delete('server')
    buf << "Server: #{_no_crlf_check(server)}#{EOL}" if server
    connection = options.delete('connection')
    buf << "Connection: #{_no_crlf_check(connection)}#{EOL}" if connection
    type = options.delete('type')
    buf << "Content-Type: #{_no_crlf_check(type)}#{EOL}" #if type
    length = options.delete('length')
    buf << "Content-Length: #{_no_crlf_check(length)}#{EOL}" if length
    language = options.delete('language')
    buf << "Content-Language: #{_no_crlf_check(language)}#{EOL}" if language
    expires = options.delete('expires')
    buf << "Expires: #{CGI.rfc1123_date(expires)}#{EOL}" if expires
    ## cookie
    if cookie = options.delete('cookie')
      case cookie
      when String, Cookie
        buf << "Set-Cookie: #{_no_crlf_check(cookie)}#{EOL}"
      when Array
        arr = cookie
        arr.each {|c| buf << "Set-Cookie: #{_no_crlf_check(c)}#{EOL}" }
      when Hash
        hash = cookie
        hash.each_value {|c| buf << "Set-Cookie: #{_no_crlf_check(c)}#{EOL}" }
      end
    end
    if @output_cookies
      @output_cookies.each {|c| buf << "Set-Cookie: #{_no_crlf_check(c)}#{EOL}" }
    end
    ## other headers
    options.each do |key, value|
      buf << "#{_no_crlf_check(key)}: #{_no_crlf_check(value)}#{EOL}"
    end
    return buf
  end # _header_for_hash
  private :_header_for_hash

  def nph?  #:nodoc:
    return /IIS\/(\d+)/ =~ $CGI_ENV['SERVER_SOFTWARE'] && $1.to_i < 5
  end

  def _header_for_modruby(buf)  #:nodoc:
    request = Apache::request
    buf.scan(/([^:]+): (.+)#{EOL}/o) do |name, value|
      $stderr.printf("name:%s value:%s\n", name, value) if $DEBUG
      case name
      when 'Set-Cookie'
        request.headers_out.add(name, value)
      when /^status$/i
        request.status_line = value
        request.status = value.to_i
      when /^content-type$/i
        request.content_type = value
      when /^content-encoding$/i
        request.content_encoding = value
      when /^location$/i
        request.status = 302 if request.status == 200
        request.headers_out[name] = value
      else
        request.headers_out[name] = value
      end
    end
    request.send_http_header
    return ''
  end
  private :_header_for_modruby

  # Print an HTTP header and body to $DEFAULT_OUTPUT ($>)
  #
  # :call-seq:
  #   cgi.out(content_type_string='text/html')
  #   cgi.out(headers_hash)
  #
  # +content_type_string+::
  #   If a string is passed, it is assumed to be the content type.
  # +headers_hash+::
  #   This is a Hash of headers, similar to that used by #http_header.
  # +block+::
  #   A block is required and should evaluate to the body of the response.
  #
  # <tt>Content-Length</tt> is automatically calculated from the size of
  # the String returned by the content block.
  #
  # If <tt>ENV['REQUEST_METHOD'] == "HEAD"</tt>, then only the header
  # is output (the content block is still required, but it is ignored).
  #
  # If the charset is "iso-2022-jp" or "euc-jp" or "shift_jis" then the
  # content is converted to this charset, and the language is set to "ja".
  #
  # Example:
  #
  #   cgi = CGI.new
  #   cgi.out{ "string" }
  #     # Content-Type: text/html
  #     # Content-Length: 6
  #     #
  #     # string
  #
  #   cgi.out("text/plain") { "string" }
  #     # Content-Type: text/plain
  #     # Content-Length: 6
  #     #
  #     # string
  #
  #   cgi.out("nph"        => true,
  #           "status"     => "OK",  # == "200 OK"
  #           "server"     => ENV['SERVER_SOFTWARE'],
  #           "connection" => "close",
  #           "type"       => "text/html",
  #           "charset"    => "iso-2022-jp",
  #             # Content-Type: text/html; charset=iso-2022-jp
  #           "language"   => "ja",
  #           "expires"    => Time.now + (3600 * 24 * 30),
  #           "cookie"     => [cookie1, cookie2],
  #           "my_header1" => "my_value",
  #           "my_header2" => "my_value") { "string" }
  #      # HTTP/1.1 200 OK
  #      # Date: Sun, 15 May 2011 17:35:54 GMT
  #      # Server: Apache 2.2.0
  #      # Connection: close
  #      # Content-Type: text/html; charset=iso-2022-jp
  #      # Content-Length: 6
  #      # Content-Language: ja
  #      # Expires: Tue, 14 Jun 2011 17:35:54 GMT
  #      # Set-Cookie: foo
  #      # Set-Cookie: bar
  #      # my_header1: my_value
  #      # my_header2: my_value
  #      #
  #      # string
  def out(options = "text/html") # :yield:

    options = { "type" => options } if options.kind_of?(String)
    content = yield
    options["length"] = content.bytesize.to_s
    output = stdoutput
    output.binmode if defined? output.binmode
    output.print http_header(options)
    output.print content unless "HEAD" == env_table['REQUEST_METHOD']
  end


  # Print an argument or list of arguments to the default output stream
  #
  #   cgi = CGI.new
  #   cgi.print    # default:  cgi.print == $DEFAULT_OUTPUT.print
  def print(*options)
    stdoutput.print(*options)
  end

  # Parse an HTTP query string into a hash of key=>value pairs.
  #
  #   params = CGI.parse("query_string")
  #     # {"name1" => ["value1", "value2", ...],
  #     #  "name2" => ["value1", "value2", ...], ... }
  #
  def self.parse(query)
    params = {}
    query.split(/[&;]/).each do |pairs|
      key, value = pairs.split('=',2).collect{|v| CGI.unescape(v) }

      next unless key

      params[key] ||= []
      params[key].push(value) if value
    end

    params.default=[].freeze
    params
  end

  # Maximum content length of post data
  ##MAX_CONTENT_LENGTH  = 2 * 1024 * 1024

  # Maximum number of request parameters when multipart
  MAX_MULTIPART_COUNT = 128

  # Mixin module that provides the following:
  #
  # 1. Access to the CGI environment variables as methods.  See
  #    documentation to the CGI class for a list of these variables.  The
  #    methods are exposed by removing the leading +HTTP_+ (if it exists) and
  #    downcasing the name.  For example, +auth_type+ will return the
  #    environment variable +AUTH_TYPE+, and +accept+ will return the value
  #    for +HTTP_ACCEPT+.
  #
  # 2. Access to cookies, including the cookies attribute.
  #
  # 3. Access to parameters, including the params attribute, and overloading
  #    #[] to perform parameter value lookup by key.
  #
  # 4. The initialize_query method, for initializing the above
  #    mechanisms, handling multipart forms, and allowing the
  #    class to be used in "offline" mode.
  #
  module QueryExtension

    %w[ CONTENT_LENGTH SERVER_PORT ].each do |env|
      define_method(env.delete_prefix('HTTP_').downcase) do
        (val = env_table[env]) && Integer(val)
      end
    end

    %w[ AUTH_TYPE CONTENT_TYPE GATEWAY_INTERFACE PATH_INFO
        PATH_TRANSLATED QUERY_STRING REMOTE_ADDR REMOTE_HOST
        REMOTE_IDENT REMOTE_USER REQUEST_METHOD SCRIPT_NAME
        SERVER_NAME SERVER_PROTOCOL SERVER_SOFTWARE

        HTTP_ACCEPT HTTP_ACCEPT_CHARSET HTTP_ACCEPT_ENCODING
        HTTP_ACCEPT_LANGUAGE HTTP_CACHE_CONTROL HTTP_FROM HTTP_HOST
        HTTP_NEGOTIATE HTTP_PRAGMA HTTP_REFERER HTTP_USER_AGENT ].each do |env|
      define_method(env.delete_prefix('HTTP_').downcase) do
        env_table[env]
      end
    end

    # Get the raw cookies as a string.
    def raw_cookie
      env_table["HTTP_COOKIE"]
    end

    # Get the raw RFC2965 cookies as a string.
    def raw_cookie2
      env_table["HTTP_COOKIE2"]
    end

    # Get the cookies as a hash of cookie-name=>Cookie pairs.
    attr_accessor :cookies

    # Get the parameters as a hash of name=>values pairs, where
    # values is an Array.
    attr_reader :params

    # Get the uploaded files as a hash of name=>values pairs
    attr_reader :files

    # Set all the parameters.
    def params=(hash)
      @params.clear
      @params.update(hash)
    end

    ##
    # Parses multipart form elements according to
    #   http://www.w3.org/TR/html401/interact/forms.html#h-17.13.4.2
    #
    # Returns a hash of multipart form parameters with bodies of type StringIO or
    # Tempfile depending on whether the multipart form element exceeds 10 KB
    #
    #   params[name => body]
    #
    def read_multipart(boundary, content_length)
      ## read first boundary
      stdin = stdinput
      first_line = "--#{boundary}#{EOL}"
      content_length -= first_line.bytesize
      status = stdin.read(first_line.bytesize)
      raise EOFError.new("no content body")  unless status
      raise EOFError.new("bad content body") unless first_line == status
      ## parse and set params
      params = {}
      @files = {}
      boundary_rexp = /--#{Regexp.quote(boundary)}(#{EOL}|--)/
      boundary_size = "#{EOL}--#{boundary}#{EOL}".bytesize
      buf = ''.dup
      bufsize = 10 * 1024
      max_count = MAX_MULTIPART_COUNT
      n = 0
      tempfiles = []
      while true
        (n += 1) < max_count or raise StandardError.new("too many parameters.")
        ## create body (StringIO or Tempfile)
        body = create_body(bufsize < content_length)
        tempfiles << body if defined?(Tempfile) && body.kind_of?(Tempfile)
        class << body
          if method_defined?(:path)
            alias local_path path
          else
            def local_path
              nil
            end
          end
          attr_reader :original_filename, :content_type
        end
        ## find head and boundary
        head = nil
        separator = EOL * 2
        until head && matched = boundary_rexp.match(buf)
          if !head && pos = buf.index(separator)
            len  = pos + EOL.bytesize
            head = buf[0, len]
            buf  = buf[(pos+separator.bytesize)..-1]
          else
            if head && buf.size > boundary_size
              len = buf.size - boundary_size
              body.print(buf[0, len])
              buf[0, len] = ''
            end
            c = stdin.read(bufsize < content_length ? bufsize : content_length)
            raise EOFError.new("bad content body") if c.nil? || c.empty?
            buf << c
            content_length -= c.bytesize
          end
        end
        ## read to end of boundary
        m = matched
        len = m.begin(0)
        s = buf[0, len]
        if s =~ /(\r?\n)\z/
          s = buf[0, len - $1.bytesize]
        end
        body.print(s)
        buf = buf[m.end(0)..-1]
        boundary_end = m[1]
        content_length = -1 if boundary_end == '--'
        ## reset file cursor position
        body.rewind
        ## original filename
        /Content-Disposition:.* filename=(?:"(.*?)"|([^;\r\n]*))/i.match(head)
        filename = $1 || $2 || ''.dup
        filename = CGI.unescape(filename) if unescape_filename?()
        body.instance_variable_set(:@original_filename, filename)
        ## content type
        /Content-Type: (.*)/i.match(head)
        (content_type = $1 || ''.dup).chomp!
        body.instance_variable_set(:@content_type, content_type)
        ## query parameter name
        /Content-Disposition:.* name=(?:"(.*?)"|([^;\r\n]*))/i.match(head)
        name = $1 || $2 || ''
        if body.original_filename.empty?
          value=body.read.dup.force_encoding(@accept_charset)
          body.close! if defined?(Tempfile) && body.kind_of?(Tempfile)
          (params[name] ||= []) << value
          unless value.valid_encoding?
            if @accept_charset_error_block
              @accept_charset_error_block.call(name,value)
            else
              raise InvalidEncoding,"Accept-Charset encoding error"
            end
          end
          class << params[name].last;self;end.class_eval do
            define_method(:read){self}
            define_method(:original_filename){""}
            define_method(:content_type){""}
          end
        else
          (params[name] ||= []) << body
          @files[name]=body
        end
        ## break loop
        break if content_length == -1
      end
      raise EOFError, "bad boundary end of body part" unless boundary_end =~ /--/
      params.default = []
      params
    rescue Exception
      if tempfiles
        tempfiles.each {|t|
          if t.path
            t.close!
          end
        }
      end
      raise
    end # read_multipart
    private :read_multipart
    def create_body(is_large)  #:nodoc:
      if is_large
        require 'tempfile'
        body = Tempfile.new('CGI', encoding: Encoding::ASCII_8BIT)
      else
        begin
          require 'stringio'
          body = StringIO.new("".b)
        rescue LoadError
          require 'tempfile'
          body = Tempfile.new('CGI', encoding: Encoding::ASCII_8BIT)
        end
      end
      body.binmode if defined? body.binmode
      return body
    end
    def unescape_filename?  #:nodoc:
      user_agent = $CGI_ENV['HTTP_USER_AGENT']
      return false unless user_agent
      return /Mac/i.match(user_agent) && /Mozilla/i.match(user_agent) && !/MSIE/i.match(user_agent)
    end

    # offline mode. read name=value pairs on standard input.
    def read_from_cmdline
      require "shellwords"

      string = unless ARGV.empty?
        ARGV.join(' ')
      else
        if STDIN.tty?
          STDERR.print(
            %|(offline mode: enter name=value pairs on standard input)\n|
          )
        end
        array = readlines rescue nil
        if not array.nil?
            array.join(' ').gsub(/\n/n, '')
        else
            ""
        end
      end.gsub(/\\=/n, '%3D').gsub(/\\&/n, '%26')

      words = Shellwords.shellwords(string)

      if words.find{|x| /=/n.match(x) }
        words.join('&')
      else
        words.join('+')
      end
    end
    private :read_from_cmdline

    # A wrapper class to use a StringIO object as the body and switch
    # to a TempFile when the passed threshold is passed.
    # Initialize the data from the query.
    #
    # Handles multipart forms (in particular, forms that involve file uploads).
    # Reads query parameters in the @params field, and cookies into @cookies.
    def initialize_query()
      if ("POST" == env_table['REQUEST_METHOD']) and
        %r|\Amultipart/form-data.*boundary=\"?([^\";,]+)\"?| =~ env_table['CONTENT_TYPE']
        current_max_multipart_length = @max_multipart_length.respond_to?(:call) ? @max_multipart_length.call : @max_multipart_length
        raise StandardError.new("too large multipart data.") if env_table['CONTENT_LENGTH'].to_i > current_max_multipart_length
        boundary = $1.dup
        @multipart = true
        @params = read_multipart(boundary, Integer(env_table['CONTENT_LENGTH']))
      else
        @multipart = false
        @params = CGI.parse(
                    case env_table['REQUEST_METHOD']
                    when "GET", "HEAD"
                      if defined?(MOD_RUBY)
                        Apache::request.args or ""
                      else
                        env_table['QUERY_STRING'] or ""
                      end
                    when "POST"
                      stdinput.binmode if defined? stdinput.binmode
                      stdinput.read(Integer(env_table['CONTENT_LENGTH'])) or ''
                    else
                      read_from_cmdline
                    end.dup.force_encoding(@accept_charset)
                  )
        unless Encoding.find(@accept_charset) == Encoding::ASCII_8BIT
          @params.each do |key,values|
            values.each do |value|
              unless value.valid_encoding?
                if @accept_charset_error_block
                  @accept_charset_error_block.call(key,value)
                else
                  raise InvalidEncoding,"Accept-Charset encoding error"
                end
              end
            end
          end
        end
      end

      @cookies = CGI::Cookie.parse((env_table['HTTP_COOKIE'] or env_table['COOKIE']))
    end
    private :initialize_query

    # Returns whether the form contained multipart/form-data
    def multipart?
      @multipart
    end

    # Get the value for the parameter with a given key.
    #
    # If the parameter has multiple values, only the first will be
    # retrieved; use #params to get the array of values.
    def [](key)
      params = @params[key]
      return '' unless params
      value = params[0]
      if @multipart
        if value
          return value
        elsif defined? StringIO
          StringIO.new("".b)
        else
          Tempfile.new("CGI",encoding: Encoding::ASCII_8BIT)
        end
      else
        str = if value then value.dup else "" end
        str
      end
    end

    # Return all query parameter names as an array of String.
    def keys(*args)
      @params.keys(*args)
    end

    # Returns true if a given query string parameter exists.
    def has_key?(*args)
      @params.has_key?(*args)
    end
    alias key? has_key?
    alias include? has_key?

  end # QueryExtension

  # Exception raised when there is an invalid encoding detected
  class InvalidEncoding < Exception; end

  # @@accept_charset is default accept character set.
  # This default value default is "UTF-8"
  # If you want to change the default accept character set
  # when create a new CGI instance, set this:
  #
  #   CGI.accept_charset = "EUC-JP"
  #
  @@accept_charset="UTF-8" if false # needed for rdoc?

  # Return the accept character set for all new CGI instances.
  def self.accept_charset
    @@accept_charset
  end

  # Set the accept character set for all new CGI instances.
  def self.accept_charset=(accept_charset)
    @@accept_charset=accept_charset
  end

  # Return the accept character set for this CGI instance.
  attr_reader :accept_charset

  # @@max_multipart_length is the maximum length of multipart data.
  # The default value is 128 * 1024 * 1024 bytes
  #
  # The default can be set to something else in the CGI constructor,
  # via the :max_multipart_length key in the option hash.
  #
  # See CGI.new documentation.
  #
  @@max_multipart_length= 128 * 1024 * 1024

  # Create a new CGI instance.
  #
  # :call-seq:
  #   CGI.new(tag_maker) { block }
  #   CGI.new(options_hash = {}) { block }
  #
  #
  # <tt>tag_maker</tt>::
  #   This is the same as using the +options_hash+ form with the value <tt>{
  #   :tag_maker => tag_maker }</tt> Note that it is recommended to use the
  #   +options_hash+ form, since it also allows you specify the charset you
  #   will accept.
  # <tt>options_hash</tt>::
  #   A Hash that recognizes three options:
  #
  #   <tt>:accept_charset</tt>::
  #     specifies encoding of received query string.  If omitted,
  #     <tt>@@accept_charset</tt> is used.  If the encoding is not valid, a
  #     CGI::InvalidEncoding will be raised.
  #
  #     Example. Suppose <tt>@@accept_charset</tt> is "UTF-8"
  #
  #     when not specified:
  #
  #         cgi=CGI.new      # @accept_charset # => "UTF-8"
  #
  #     when specified as "EUC-JP":
  #
  #         cgi=CGI.new(:accept_charset => "EUC-JP") # => "EUC-JP"
  #
  #   <tt>:tag_maker</tt>::
  #     String that specifies which version of the HTML generation methods to
  #     use.  If not specified, no HTML generation methods will be loaded.
  #
  #     The following values are supported:
  #
  #     "html3":: HTML 3.x
  #     "html4":: HTML 4.0
  #     "html4Tr":: HTML 4.0 Transitional
  #     "html4Fr":: HTML 4.0 with Framesets
  #     "html5":: HTML 5
  #
  #   <tt>:max_multipart_length</tt>::
  #     Specifies maximum length of multipart data. Can be an Integer scalar or
  #     a lambda, that will be evaluated when the request is parsed. This
  #     allows more complex logic to be set when determining whether to accept
  #     multipart data (e.g. consult a registered users upload allowance)
  #
  #     Default is 128 * 1024 * 1024 bytes
  #
  #         cgi=CGI.new(:max_multipart_length => 268435456) # simple scalar
  #
  #         cgi=CGI.new(:max_multipart_length => -> {check_filesystem}) # lambda
  #
  # <tt>block</tt>::
  #   If provided, the block is called when an invalid encoding is
  #   encountered. For example:
  #
  #     encoding_errors={}
  #     cgi=CGI.new(:accept_charset=>"EUC-JP") do |name,value|
  #       encoding_errors[name] = value
  #     end
  #
  # Finally, if the CGI object is not created in a standard CGI call
  # environment (that is, it can't locate REQUEST_METHOD in its environment),
  # then it will run in "offline" mode.  In this mode, it reads its parameters
  # from the command line or (failing that) from standard input.  Otherwise,
  # cookies and other parameters are parsed automatically from the standard
  # CGI locations, which varies according to the REQUEST_METHOD.
  def initialize(options = {}, &block) # :yields: name, value
    @accept_charset_error_block = block_given? ? block : nil
    @options={
      :accept_charset=>@@accept_charset,
      :max_multipart_length=>@@max_multipart_length
    }
    case options
    when Hash
      @options.merge!(options)
    when String
      @options[:tag_maker]=options
    end
    @accept_charset=@options[:accept_charset]
    @max_multipart_length=@options[:max_multipart_length]
    if defined?(MOD_RUBY) && !ENV.key?("GATEWAY_INTERFACE")
      Apache.request.setup_cgi_env
    end

    extend QueryExtension
    @multipart = false

    initialize_query()  # set @params, @cookies
    @output_cookies = nil
    @output_hidden = nil

    case @options[:tag_maker]
    when "html3"
      require_relative 'html'
      extend Html3
      extend HtmlExtension
    when "html4"
      require_relative 'html'
      extend Html4
      extend HtmlExtension
    when "html4Tr"
      require_relative 'html'
      extend Html4Tr
      extend HtmlExtension
    when "html4Fr"
      require_relative 'html'
      extend Html4Tr
      extend Html4Fr
      extend HtmlExtension
    when "html5"
      require_relative 'html'
      extend Html5
      extend HtmlExtension
    end
  end

end   # class CGI
