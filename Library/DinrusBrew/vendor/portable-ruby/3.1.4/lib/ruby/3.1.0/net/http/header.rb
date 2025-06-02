# frozen_string_literal: false
# The HTTPHeader module defines methods for reading and writing
# HTTP headers.
#
# It is used as a mixin by other classes, to provide hash-like
# access to HTTP header values. Unlike raw hash access, HTTPHeader
# provides access via case-insensitive keys. It also provides
# methods for accessing commonly-used HTTP header values in more
# convenient formats.
#
module Net::HTTPHeader

  def initialize_http_header(initheader)
    @header = {}
    return unless initheader
    initheader.each do |key, value|
      warn "net/http: duplicated HTTP header: #{key}", uplevel: 3 if key?(key) and $VERBOSE
      if value.nil?
        warn "net/http: nil HTTP header: #{key}", uplevel: 3 if $VERBOSE
      else
        value = value.strip # raise error for invalid byte sequences
        if value.count("\r\n") > 0
          raise ArgumentError, "header #{key} has field value #{value.inspect}, this cannot include CR/LF"
        end
        @header[key.downcase.to_s] = [value]
      end
    end
  end

  def size   #:nodoc: obsolete
    @header.size
  end

  alias length size   #:nodoc: obsolete

  # Returns the header field corresponding to the case-insensitive key.
  # For example, a key of "Content-Type" might return "text/html"
  def [](key)
    a = @header[key.downcase.to_s] or return nil
    a.join(', ')
  end

  # Sets the header field corresponding to the case-insensitive key.
  def []=(key, val)
    unless val
      @header.delete key.downcase.to_s
      return val
    end
    set_field(key, val)
  end

  # [Ruby 1.8.3]
  # Adds a value to a named header field, instead of replacing its value.
  # Second argument +val+ must be a String.
  # See also #[]=, #[] and #get_fields.
  #
  #   request.add_field 'X-My-Header', 'a'
  #   p request['X-My-Header']              #=> "a"
  #   p request.get_fields('X-My-Header')   #=> ["a"]
  #   request.add_field 'X-My-Header', 'b'
  #   p request['X-My-Header']              #=> "a, b"
  #   p request.get_fields('X-My-Header')   #=> ["a", "b"]
  #   request.add_field 'X-My-Header', 'c'
  #   p request['X-My-Header']              #=> "a, b, c"
  #   p request.get_fields('X-My-Header')   #=> ["a", "b", "c"]
  #
  def add_field(key, val)
    stringified_downcased_key = key.downcase.to_s
    if @header.key?(stringified_downcased_key)
      append_field_value(@header[stringified_downcased_key], val)
    else
      set_field(key, val)
    end
  end

  private def set_field(key, val)
    case val
    when Enumerable
      ary = []
      append_field_value(ary, val)
      @header[key.downcase.to_s] = ary
    else
      val = val.to_s # for compatibility use to_s instead of to_str
      if val.b.count("\r\n") > 0
        raise ArgumentError, 'header field value cannot include CR/LF'
      end
      @header[key.downcase.to_s] = [val]
    end
  end

  private def append_field_value(ary, val)
    case val
    when Enumerable
      val.each{|x| append_field_value(ary, x)}
    else
      val = val.to_s
      if /[\r\n]/n.match?(val.b)
        raise ArgumentError, 'header field value cannot include CR/LF'
      end
      ary.push val
    end
  end

  # [Ruby 1.8.3]
  # Returns an array of header field strings corresponding to the
  # case-insensitive +key+.  This method allows you to get duplicated
  # header fields without any processing.  See also #[].
  #
  #   p response.get_fields('Set-Cookie')
  #     #=> ["session=al98axx; expires=Fri, 31-Dec-1999 23:58:23",
  #          "query=rubyscript; expires=Fri, 31-Dec-1999 23:58:23"]
  #   p response['Set-Cookie']
  #     #=> "session=al98axx; expires=Fri, 31-Dec-1999 23:58:23, query=rubyscript; expires=Fri, 31-Dec-1999 23:58:23"
  #
  def get_fields(key)
    stringified_downcased_key = key.downcase.to_s
    return nil unless @header[stringified_downcased_key]
    @header[stringified_downcased_key].dup
  end

  # Returns the header field corresponding to the case-insensitive key.
  # Returns the default value +args+, or the result of the block, or
  # raises an IndexError if there's no header field named +key+
  # See Hash#fetch
  def fetch(key, *args, &block)   #:yield: +key+
    a = @header.fetch(key.downcase.to_s, *args, &block)
    a.kind_of?(Array) ? a.join(', ') : a
  end

  # Iterates through the header names and values, passing in the name
  # and value to the code block supplied.
  #
  # Returns an enumerator if no block is given.
  #
  # Example:
  #
  #     response.header.each_header {|key,value| puts "#{key} = #{value}" }
  #
  def each_header   #:yield: +key+, +value+
    block_given? or return enum_for(__method__) { @header.size }
    @header.each do |k,va|
      yield k, va.join(', ')
    end
  end

  alias each each_header

  # Iterates through the header names in the header, passing
  # each header name to the code block.
  #
  # Returns an enumerator if no block is given.
  def each_name(&block)   #:yield: +key+
    block_given? or return enum_for(__method__) { @header.size }
    @header.each_key(&block)
  end

  alias each_key each_name

  # Iterates through the header names in the header, passing
  # capitalized header names to the code block.
  #
  # Note that header names are capitalized systematically;
  # capitalization may not match that used by the remote HTTP
  # server in its response.
  #
  # Returns an enumerator if no block is given.
  def each_capitalized_name  #:yield: +key+
    block_given? or return enum_for(__method__) { @header.size }
    @header.each_key do |k|
      yield capitalize(k)
    end
  end

  # Iterates through header values, passing each value to the
  # code block.
  #
  # Returns an enumerator if no block is given.
  def each_value   #:yield: +value+
    block_given? or return enum_for(__method__) { @header.size }
    @header.each_value do |va|
      yield va.join(', ')
    end
  end

  # Removes a header field, specified by case-insensitive key.
  def delete(key)
    @header.delete(key.downcase.to_s)
  end

  # true if +key+ header exists.
  def key?(key)
    @header.key?(key.downcase.to_s)
  end

  # Returns a Hash consisting of header names and array of values.
  # e.g.
  # {"cache-control" => ["private"],
  #  "content-type" => ["text/html"],
  #  "date" => ["Wed, 22 Jun 2005 22:11:50 GMT"]}
  def to_hash
    @header.dup
  end

  # As for #each_header, except the keys are provided in capitalized form.
  #
  # Note that header names are capitalized systematically;
  # capitalization may not match that used by the remote HTTP
  # server in its response.
  #
  # Returns an enumerator if no block is given.
  def each_capitalized
    block_given? or return enum_for(__method__) { @header.size }
    @header.each do |k,v|
      yield capitalize(k), v.join(', ')
    end
  end

  alias canonical_each each_capitalized

  def capitalize(name)
    name.to_s.split(/-/).map {|s| s.capitalize }.join('-')
  end
  private :capitalize

  # Returns an Array of Range objects which represent the Range:
  # HTTP header field, or +nil+ if there is no such header.
  def range
    return nil unless @header['range']

    value = self['Range']
    # byte-range-set = *( "," OWS ) ( byte-range-spec / suffix-byte-range-spec )
    #   *( OWS "," [ OWS ( byte-range-spec / suffix-byte-range-spec ) ] )
    # corrected collected ABNF
    # http://tools.ietf.org/html/draft-ietf-httpbis-p5-range-19#section-5.4.1
    # http://tools.ietf.org/html/draft-ietf-httpbis-p5-range-19#appendix-C
    # http://tools.ietf.org/html/draft-ietf-httpbis-p1-messaging-19#section-3.2.5
    unless /\Abytes=((?:,[ \t]*)*(?:\d+-\d*|-\d+)(?:[ \t]*,(?:[ \t]*\d+-\d*|-\d+)?)*)\z/ =~ value
      raise Net::HTTPHeaderSyntaxError, "invalid syntax for byte-ranges-specifier: '#{value}'"
    end

    byte_range_set = $1
    result = byte_range_set.split(/,/).map {|spec|
      m = /(\d+)?\s*-\s*(\d+)?/i.match(spec) or
              raise Net::HTTPHeaderSyntaxError, "invalid byte-range-spec: '#{spec}'"
      d1 = m[1].to_i
      d2 = m[2].to_i
      if m[1] and m[2]
        if d1 > d2
          raise Net::HTTPHeaderSyntaxError, "last-byte-pos MUST greater than or equal to first-byte-pos but '#{spec}'"
        end
        d1..d2
      elsif m[1]
        d1..-1
      elsif m[2]
        -d2..-1
      else
        raise Net::HTTPHeaderSyntaxError, 'range is not specified'
      end
    }
    # if result.empty?
    # byte-range-set must include at least one byte-range-spec or suffix-byte-range-spec
    # but above regexp already denies it.
    if result.size == 1 && result[0].begin == 0 && result[0].end == -1
      raise Net::HTTPHeaderSyntaxError, 'only one suffix-byte-range-spec with zero suffix-length'
    end
    result
  end

  # Sets the HTTP Range: header.
  # Accepts either a Range object as a single argument,
  # or a beginning index and a length from that index.
  # Example:
  #
  #   req.range = (0..1023)
  #   req.set_range 0, 1023
  #
  def set_range(r, e = nil)
    unless r
      @header.delete 'range'
      return r
    end
    r = (r...r+e) if e
    case r
    when Numeric
      n = r.to_i
      rangestr = (n > 0 ? "0-#{n-1}" : "-#{-n}")
    when Range
      first = r.first
      last = r.end
      last -= 1 if r.exclude_end?
      if last == -1
        rangestr = (first > 0 ? "#{first}-" : "-#{-first}")
      else
        raise Net::HTTPHeaderSyntaxError, 'range.first is negative' if first < 0
        raise Net::HTTPHeaderSyntaxError, 'range.last is negative' if last < 0
        raise Net::HTTPHeaderSyntaxError, 'must be .first < .last' if first > last
        rangestr = "#{first}-#{last}"
      end
    else
      raise TypeError, 'Range/Integer is required'
    end
    @header['range'] = ["bytes=#{rangestr}"]
    r
  end

  alias range= set_range

  # Returns an Integer object which represents the HTTP Content-Length:
  # header field, or +nil+ if that field was not provided.
  def content_length
    return nil unless key?('Content-Length')
    len = self['Content-Length'].slice(/\d+/) or
        raise Net::HTTPHeaderSyntaxError, 'wrong Content-Length format'
    len.to_i
  end

  def content_length=(len)
    unless len
      @header.delete 'content-length'
      return nil
    end
    @header['content-length'] = [len.to_i.to_s]
  end

  # Returns "true" if the "transfer-encoding" header is present and
  # set to "chunked".  This is an HTTP/1.1 feature, allowing
  # the content to be sent in "chunks" without at the outset
  # stating the entire content length.
  def chunked?
    return false unless @header['transfer-encoding']
    field = self['Transfer-Encoding']
    (/(?:\A|[^\-\w])chunked(?![\-\w])/i =~ field) ? true : false
  end

  # Returns a Range object which represents the value of the Content-Range:
  # header field.
  # For a partial entity body, this indicates where this fragment
  # fits inside the full entity body, as range of byte offsets.
  def content_range
    return nil unless @header['content-range']
    m = %r<\A\s*(\w+)\s+(\d+)-(\d+)/(\d+|\*)>.match(self['Content-Range']) or
        raise Net::HTTPHeaderSyntaxError, 'wrong Content-Range format'
    return unless m[1] == 'bytes'
    m[2].to_i .. m[3].to_i
  end

  # The length of the range represented in Content-Range: header.
  def range_length
    r = content_range() or return nil
    r.end - r.begin + 1
  end

  # Returns a content type string such as "text/html".
  # This method returns nil if Content-Type: header field does not exist.
  def content_type
    return nil unless main_type()
    if sub_type()
    then "#{main_type()}/#{sub_type()}"
    else main_type()
    end
  end

  # Returns a content type string such as "text".
  # This method returns nil if Content-Type: header field does not exist.
  def main_type
    return nil unless @header['content-type']
    self['Content-Type'].split(';').first.to_s.split('/')[0].to_s.strip
  end

  # Returns a content type string such as "html".
  # This method returns nil if Content-Type: header field does not exist
  # or sub-type is not given (e.g. "Content-Type: text").
  def sub_type
    return nil unless @header['content-type']
    _, sub = *self['Content-Type'].split(';').first.to_s.split('/')
    return nil unless sub
    sub.strip
  end

  # Any parameters specified for the content type, returned as a Hash.
  # For example, a header of Content-Type: text/html; charset=EUC-JP
  # would result in type_params returning {'charset' => 'EUC-JP'}
  def type_params
    result = {}
    list = self['Content-Type'].to_s.split(';')
    list.shift
    list.each do |param|
      k, v = *param.split('=', 2)
      result[k.strip] = v.strip
    end
    result
  end

  # Sets the content type in an HTTP header.
  # The +type+ should be a full HTTP content type, e.g. "text/html".
  # The +params+ are an optional Hash of parameters to add after the
  # content type, e.g. {'charset' => 'iso-8859-1'}
  def set_content_type(type, params = {})
    @header['content-type'] = [type + params.map{|k,v|"; #{k}=#{v}"}.join('')]
  end

  alias content_type= set_content_type

  # Set header fields and a body from HTML form data.
  # +params+ should be an Array of Arrays or
  # a Hash containing HTML form data.
  # Optional argument +sep+ means data record separator.
  #
  # Values are URL encoded as necessary and the content-type is set to
  # application/x-www-form-urlencoded
  #
  # Example:
  #    http.form_data = {"q" => "ruby", "lang" => "en"}
  #    http.form_data = {"q" => ["ruby", "perl"], "lang" => "en"}
  #    http.set_form_data({"q" => "ruby", "lang" => "en"}, ';')
  #
  def set_form_data(params, sep = '&')
    query = URI.encode_www_form(params)
    query.gsub!(/&/, sep) if sep != '&'
    self.body = query
    self.content_type = 'application/x-www-form-urlencoded'
  end

  alias form_data= set_form_data

  # Set an HTML form data set.
  # +params+ :: The form data to set, which should be an enumerable.
  #             See below for more details.
  # +enctype+ :: The content type to use to encode the form submission,
  #              which should be application/x-www-form-urlencoded or
  #              multipart/form-data.
  # +formopt+ :: An options hash, supporting the following options:
  #              :boundary :: The boundary of the multipart message. If
  #                           not given, a random boundary will be used.
  #              :charset :: The charset of the form submission. All
  #                          field names and values of non-file fields
  #                          should be encoded with this charset.
  #
  # Each item of params should respond to +each+ and yield 2-3 arguments,
  # or an array of 2-3 elements. The arguments yielded should be:
  #  * The name of the field.
  #  * The value of the field, it should be a String or a File or IO-like.
  #  * An options hash, supporting the following options, only
  #    used for file uploads:
  #    :filename :: The name of the file to use.
  #    :content_type :: The content type of the uploaded file.
  #
  # Each item is a file field or a normal field.
  # If +value+ is a File object or the +opt+ hash has a :filename key,
  # the item is treated as a file field.
  #
  # If Transfer-Encoding is set as chunked, this sends the request using
  # chunked encoding. Because chunked encoding is HTTP/1.1 feature,
  # you should confirm that the server supports HTTP/1.1 before using
  # chunked encoding.
  #
  # Example:
  #    req.set_form([["q", "ruby"], ["lang", "en"]])
  #
  #    req.set_form({"f"=>File.open('/path/to/filename')},
  #                 "multipart/form-data",
  #                 charset: "UTF-8",
  #    )
  #
  #    req.set_form([["f",
  #                   File.open('/path/to/filename.bar'),
  #                   {filename: "other-filename.foo"}
  #                 ]],
  #                 "multipart/form-data",
  #    )
  #
  # See also RFC 2388, RFC 2616, HTML 4.01, and HTML5
  #
  def set_form(params, enctype='application/x-www-form-urlencoded', formopt={})
    @body_data = params
    @body = nil
    @body_stream = nil
    @form_option = formopt
    case enctype
    when /\Aapplication\/x-www-form-urlencoded\z/i,
      /\Amultipart\/form-data\z/i
      self.content_type = enctype
    else
      raise ArgumentError, "invalid enctype: #{enctype}"
    end
  end

  # Set the Authorization: header for "Basic" authorization.
  def basic_auth(account, password)
    @header['authorization'] = [basic_encode(account, password)]
  end

  # Set Proxy-Authorization: header for "Basic" authorization.
  def proxy_basic_auth(account, password)
    @header['proxy-authorization'] = [basic_encode(account, password)]
  end

  def basic_encode(account, password)
    'Basic ' + ["#{account}:#{password}"].pack('m0')
  end
  private :basic_encode

  def connection_close?
    token = /(?:\A|,)\s*close\s*(?:\z|,)/i
    @header['connection']&.grep(token) {return true}
    @header['proxy-connection']&.grep(token) {return true}
    false
  end

  def connection_keep_alive?
    token = /(?:\A|,)\s*keep-alive\s*(?:\z|,)/i
    @header['connection']&.grep(token) {return true}
    @header['proxy-connection']&.grep(token) {return true}
    false
  end

end
