# frozen_string_literal: true
#--
# = uri/common.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License::
#   You can redistribute it and/or modify it under the same term as Ruby.
#
# See Gem::URI for general documentation
#

require_relative "rfc2396_parser"
require_relative "rfc3986_parser"

module Gem::URI
  include RFC2396_REGEXP

  REGEXP = RFC2396_REGEXP
  Parser = RFC2396_Parser
  RFC3986_PARSER = RFC3986_Parser.new
  Ractor.make_shareable(RFC3986_PARSER) if defined?(Ractor)
  RFC2396_PARSER = RFC2396_Parser.new
  Ractor.make_shareable(RFC2396_PARSER) if defined?(Ractor)

  # Gem::URI::Parser.new
  DEFAULT_PARSER = Parser.new
  DEFAULT_PARSER.pattern.each_pair do |sym, str|
    unless REGEXP::PATTERN.const_defined?(sym)
      REGEXP::PATTERN.const_set(sym, str)
    end
  end
  DEFAULT_PARSER.regexp.each_pair do |sym, str|
    const_set(sym, str)
  end
  Ractor.make_shareable(DEFAULT_PARSER) if defined?(Ractor)

  module Util # :nodoc:
    def make_components_hash(klass, array_hash)
      tmp = {}
      if array_hash.kind_of?(Array) &&
          array_hash.size == klass.component.size - 1
        klass.component[1..-1].each_index do |i|
          begin
            tmp[klass.component[i + 1]] = array_hash[i].clone
          rescue TypeError
            tmp[klass.component[i + 1]] = array_hash[i]
          end
        end

      elsif array_hash.kind_of?(Hash)
        array_hash.each do |key, value|
          begin
            tmp[key] = value.clone
          rescue TypeError
            tmp[key] = value
          end
        end
      else
        raise ArgumentError,
          "expected Array of or Hash of components of #{klass} (#{klass.component[1..-1].join(', ')})"
      end
      tmp[:scheme] = klass.to_s.sub(/\A.*::/, '').downcase

      return tmp
    end
    module_function :make_components_hash
  end

  module Schemes
  end
  private_constant :Schemes

  # Registers the given +klass+ as the class to be instantiated
  # when parsing a \Gem::URI with the given +scheme+:
  #
  #   Gem::URI.register_scheme('MS_SEARCH', Gem::URI::Generic) # => Gem::URI::Generic
  #   Gem::URI.scheme_list['MS_SEARCH']                   # => Gem::URI::Generic
  #
  # Note that after calling String#upcase on +scheme+, it must be a valid
  # constant name.
  def self.register_scheme(scheme, klass)
    Schemes.const_set(scheme.to_s.upcase, klass)
  end

  # Returns a hash of the defined schemes:
  #
  #   Gem::URI.scheme_list
  #   # =>
  #   {"MAILTO"=>Gem::URI::MailTo,
  #    "LDAPS"=>Gem::URI::LDAPS,
  #    "WS"=>Gem::URI::WS,
  #    "HTTP"=>Gem::URI::HTTP,
  #    "HTTPS"=>Gem::URI::HTTPS,
  #    "LDAP"=>Gem::URI::LDAP,
  #    "FILE"=>Gem::URI::File,
  #    "FTP"=>Gem::URI::FTP}
  #
  # Related: Gem::URI.register_scheme.
  def self.scheme_list
    Schemes.constants.map { |name|
      [name.to_s.upcase, Schemes.const_get(name)]
    }.to_h
  end

  INITIAL_SCHEMES = scheme_list
  private_constant :INITIAL_SCHEMES
  Ractor.make_shareable(INITIAL_SCHEMES) if defined?(Ractor)

  # Returns a new object constructed from the given +scheme+, +arguments+,
  # and +default+:
  #
  # - The new object is an instance of <tt>Gem::URI.scheme_list[scheme.upcase]</tt>.
  # - The object is initialized by calling the class initializer
  #   using +scheme+ and +arguments+.
  #   See Gem::URI::Generic.new.
  #
  # Examples:
  #
  #   values = ['john.doe', 'www.example.com', '123', nil, '/forum/questions/', nil, 'tag=networking&order=newest', 'top']
  #   Gem::URI.for('https', *values)
  #   # => #<Gem::URI::HTTPS https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top>
  #   Gem::URI.for('foo', *values, default: Gem::URI::HTTP)
  #   # => #<Gem::URI::HTTP foo://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top>
  #
  def self.for(scheme, *arguments, default: Generic)
    const_name = scheme.to_s.upcase

    uri_class = INITIAL_SCHEMES[const_name]
    uri_class ||= if /\A[A-Z]\w*\z/.match?(const_name) && Schemes.const_defined?(const_name, false)
      Schemes.const_get(const_name, false)
    end
    uri_class ||= default

    return uri_class.new(scheme, *arguments)
  end

  #
  # Base class for all Gem::URI exceptions.
  #
  class Error < StandardError; end
  #
  # Not a Gem::URI.
  #
  class InvalidURIError < Error; end
  #
  # Not a Gem::URI component.
  #
  class InvalidComponentError < Error; end
  #
  # Gem::URI is valid, bad usage is not.
  #
  class BadURIError < Error; end

  # Returns a 9-element array representing the parts of the \Gem::URI
  # formed from the string +uri+;
  # each array element is a string or +nil+:
  #
  #   names = %w[scheme userinfo host port registry path opaque query fragment]
  #   values = Gem::URI.split('https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top')
  #   names.zip(values)
  #   # =>
  #   [["scheme", "https"],
  #    ["userinfo", "john.doe"],
  #    ["host", "www.example.com"],
  #    ["port", "123"],
  #    ["registry", nil],
  #    ["path", "/forum/questions/"],
  #    ["opaque", nil],
  #    ["query", "tag=networking&order=newest"],
  #    ["fragment", "top"]]
  #
  def self.split(uri)
    RFC3986_PARSER.split(uri)
  end

  # Returns a new \Gem::URI object constructed from the given string +uri+:
  #
  #   Gem::URI.parse('https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top')
  #   # => #<Gem::URI::HTTPS https://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top>
  #   Gem::URI.parse('http://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top')
  #   # => #<Gem::URI::HTTP http://john.doe@www.example.com:123/forum/questions/?tag=networking&order=newest#top>
  #
  # It's recommended to first ::escape string +uri+
  # if it may contain invalid Gem::URI characters.
  #
  def self.parse(uri)
    RFC3986_PARSER.parse(uri)
  end

  # Merges the given Gem::URI strings +str+
  # per {RFC 2396}[https://www.rfc-editor.org/rfc/rfc2396.html].
  #
  # Each string in +str+ is converted to an
  # {RFC3986 Gem::URI}[https://www.rfc-editor.org/rfc/rfc3986.html] before being merged.
  #
  # Examples:
  #
  #   Gem::URI.join("http://example.com/","main.rbx")
  #   # => #<Gem::URI::HTTP http://example.com/main.rbx>
  #
  #   Gem::URI.join('http://example.com', 'foo')
  #   # => #<Gem::URI::HTTP http://example.com/foo>
  #
  #   Gem::URI.join('http://example.com', '/foo', '/bar')
  #   # => #<Gem::URI::HTTP http://example.com/bar>
  #
  #   Gem::URI.join('http://example.com', '/foo', 'bar')
  #   # => #<Gem::URI::HTTP http://example.com/bar>
  #
  #   Gem::URI.join('http://example.com', '/foo/', 'bar')
  #   # => #<Gem::URI::HTTP http://example.com/foo/bar>
  #
  def self.join(*str)
    RFC3986_PARSER.join(*str)
  end

  #
  # == Synopsis
  #
  #   Gem::URI::extract(str[, schemes][,&blk])
  #
  # == Args
  #
  # +str+::
  #   String to extract URIs from.
  # +schemes+::
  #   Limit Gem::URI matching to specific schemes.
  #
  # == Description
  #
  # Extracts URIs from a string. If block given, iterates through all matched URIs.
  # Returns nil if block given or array with matches.
  #
  # == Usage
  #
  #   require "rubygems/vendor/uri/lib/uri"
  #
  #   Gem::URI.extract("text here http://foo.example.org/bla and here mailto:test@example.com and here also.")
  #   # => ["http://foo.example.com/bla", "mailto:test@example.com"]
  #
  def self.extract(str, schemes = nil, &block) # :nodoc:
    warn "Gem::URI.extract is obsolete", uplevel: 1 if $VERBOSE
    DEFAULT_PARSER.extract(str, schemes, &block)
  end

  #
  # == Synopsis
  #
  #   Gem::URI::regexp([match_schemes])
  #
  # == Args
  #
  # +match_schemes+::
  #   Array of schemes. If given, resulting regexp matches to URIs
  #   whose scheme is one of the match_schemes.
  #
  # == Description
  #
  # Returns a Regexp object which matches to Gem::URI-like strings.
  # The Regexp object returned by this method includes arbitrary
  # number of capture group (parentheses).  Never rely on its number.
  #
  # == Usage
  #
  #   require 'rubygems/vendor/uri/lib/uri'
  #
  #   # extract first Gem::URI from html_string
  #   html_string.slice(Gem::URI.regexp)
  #
  #   # remove ftp URIs
  #   html_string.sub(Gem::URI.regexp(['ftp']), '')
  #
  #   # You should not rely on the number of parentheses
  #   html_string.scan(Gem::URI.regexp) do |*matches|
  #     p $&
  #   end
  #
  def self.regexp(schemes = nil)# :nodoc:
    warn "Gem::URI.regexp is obsolete", uplevel: 1 if $VERBOSE
    DEFAULT_PARSER.make_regexp(schemes)
  end

  TBLENCWWWCOMP_ = {} # :nodoc:
  256.times do |i|
    TBLENCWWWCOMP_[-i.chr] = -('%%%02X' % i)
  end
  TBLENCURICOMP_ = TBLENCWWWCOMP_.dup.freeze
  TBLENCWWWCOMP_[' '] = '+'
  TBLENCWWWCOMP_.freeze
  TBLDECWWWCOMP_ = {} # :nodoc:
  256.times do |i|
    h, l = i>>4, i&15
    TBLDECWWWCOMP_[-('%%%X%X' % [h, l])] = -i.chr
    TBLDECWWWCOMP_[-('%%%x%X' % [h, l])] = -i.chr
    TBLDECWWWCOMP_[-('%%%X%x' % [h, l])] = -i.chr
    TBLDECWWWCOMP_[-('%%%x%x' % [h, l])] = -i.chr
  end
  TBLDECWWWCOMP_['+'] = ' '
  TBLDECWWWCOMP_.freeze

  # Returns a URL-encoded string derived from the given string +str+.
  #
  # The returned string:
  #
  # - Preserves:
  #
  #   - Characters <tt>'*'</tt>, <tt>'.'</tt>, <tt>'-'</tt>, and <tt>'_'</tt>.
  #   - Character in ranges <tt>'a'..'z'</tt>, <tt>'A'..'Z'</tt>,
  #     and <tt>'0'..'9'</tt>.
  #
  #   Example:
  #
  #     Gem::URI.encode_www_form_component('*.-_azAZ09')
  #     # => "*.-_azAZ09"
  #
  # - Converts:
  #
  #   - Character <tt>' '</tt> to character <tt>'+'</tt>.
  #   - Any other character to "percent notation";
  #     the percent notation for character <i>c</i> is <tt>'%%%X' % c.ord</tt>.
  #
  #   Example:
  #
  #     Gem::URI.encode_www_form_component('Here are some punctuation characters: ,;?:')
  #     # => "Here+are+some+punctuation+characters%3A+%2C%3B%3F%3A"
  #
  # Encoding:
  #
  # - If +str+ has encoding Encoding::ASCII_8BIT, argument +enc+ is ignored.
  # - Otherwise +str+ is converted first to Encoding::UTF_8
  #   (with suitable character replacements),
  #   and then to encoding +enc+.
  #
  # In either case, the returned string has forced encoding Encoding::US_ASCII.
  #
  # Related: Gem::URI.encode_uri_component (encodes <tt>' '</tt> as <tt>'%20'</tt>).
  def self.encode_www_form_component(str, enc=nil)
    _encode_uri_component(/[^*\-.0-9A-Z_a-z]/, TBLENCWWWCOMP_, str, enc)
  end

  # Returns a string decoded from the given \URL-encoded string +str+.
  #
  # The given string is first encoded as Encoding::ASCII-8BIT (using String#b),
  # then decoded (as below), and finally force-encoded to the given encoding +enc+.
  #
  # The returned string:
  #
  # - Preserves:
  #
  #   - Characters <tt>'*'</tt>, <tt>'.'</tt>, <tt>'-'</tt>, and <tt>'_'</tt>.
  #   - Character in ranges <tt>'a'..'z'</tt>, <tt>'A'..'Z'</tt>,
  #     and <tt>'0'..'9'</tt>.
  #
  #   Example:
  #
  #     Gem::URI.decode_www_form_component('*.-_azAZ09')
  #     # => "*.-_azAZ09"
  #
  # - Converts:
  #
  #   - Character <tt>'+'</tt> to character <tt>' '</tt>.
  #   - Each "percent notation" to an ASCII character.
  #
  #   Example:
  #
  #     Gem::URI.decode_www_form_component('Here+are+some+punctuation+characters%3A+%2C%3B%3F%3A')
  #     # => "Here are some punctuation characters: ,;?:"
  #
  # Related: Gem::URI.decode_uri_component (preserves <tt>'+'</tt>).
  def self.decode_www_form_component(str, enc=Encoding::UTF_8)
    _decode_uri_component(/\+|%\h\h/, str, enc)
  end

  # Like Gem::URI.encode_www_form_component, except that <tt>' '</tt> (space)
  # is encoded as <tt>'%20'</tt> (instead of <tt>'+'</tt>).
  def self.encode_uri_component(str, enc=nil)
    _encode_uri_component(/[^*\-.0-9A-Z_a-z]/, TBLENCURICOMP_, str, enc)
  end

  # Like Gem::URI.decode_www_form_component, except that <tt>'+'</tt> is preserved.
  def self.decode_uri_component(str, enc=Encoding::UTF_8)
    _decode_uri_component(/%\h\h/, str, enc)
  end

  def self._encode_uri_component(regexp, table, str, enc)
    str = str.to_s.dup
    if str.encoding != Encoding::ASCII_8BIT
      if enc && enc != Encoding::ASCII_8BIT
        str.encode!(Encoding::UTF_8, invalid: :replace, undef: :replace)
        str.encode!(enc, fallback: ->(x){"&##{x.ord};"})
      end
      str.force_encoding(Encoding::ASCII_8BIT)
    end
    str.gsub!(regexp, table)
    str.force_encoding(Encoding::US_ASCII)
  end
  private_class_method :_encode_uri_component

  def self._decode_uri_component(regexp, str, enc)
    raise ArgumentError, "invalid %-encoding (#{str})" if /%(?!\h\h)/.match?(str)
    str.b.gsub(regexp, TBLDECWWWCOMP_).force_encoding(enc)
  end
  private_class_method :_decode_uri_component

  # Returns a URL-encoded string derived from the given
  # {Enumerable}[rdoc-ref:Enumerable@Enumerable+in+Ruby+Classes]
  # +enum+.
  #
  # The result is suitable for use as form data
  # for an \HTTP request whose <tt>Content-Type</tt> is
  # <tt>'application/x-www-form-urlencoded'</tt>.
  #
  # The returned string consists of the elements of +enum+,
  # each converted to one or more URL-encoded strings,
  # and all joined with character <tt>'&'</tt>.
  #
  # Simple examples:
  #
  #   Gem::URI.encode_www_form([['foo', 0], ['bar', 1], ['baz', 2]])
  #   # => "foo=0&bar=1&baz=2"
  #   Gem::URI.encode_www_form({foo: 0, bar: 1, baz: 2})
  #   # => "foo=0&bar=1&baz=2"
  #
  # The returned string is formed using method Gem::URI.encode_www_form_component,
  # which converts certain characters:
  #
  #   Gem::URI.encode_www_form('f#o': '/', 'b-r': '$', 'b z': '@')
  #   # => "f%23o=%2F&b-r=%24&b+z=%40"
  #
  # When +enum+ is Array-like, each element +ele+ is converted to a field:
  #
  # - If +ele+ is an array of two or more elements,
  #   the field is formed from its first two elements
  #   (and any additional elements are ignored):
  #
  #     name = Gem::URI.encode_www_form_component(ele[0], enc)
  #     value = Gem::URI.encode_www_form_component(ele[1], enc)
  #     "#{name}=#{value}"
  #
  #   Examples:
  #
  #     Gem::URI.encode_www_form([%w[foo bar], %w[baz bat bah]])
  #     # => "foo=bar&baz=bat"
  #     Gem::URI.encode_www_form([['foo', 0], ['bar', :baz, 'bat']])
  #     # => "foo=0&bar=baz"
  #
  # - If +ele+ is an array of one element,
  #   the field is formed from <tt>ele[0]</tt>:
  #
  #     Gem::URI.encode_www_form_component(ele[0])
  #
  #   Example:
  #
  #     Gem::URI.encode_www_form([['foo'], [:bar], [0]])
  #     # => "foo&bar&0"
  #
  # - Otherwise the field is formed from +ele+:
  #
  #     Gem::URI.encode_www_form_component(ele)
  #
  #   Example:
  #
  #     Gem::URI.encode_www_form(['foo', :bar, 0])
  #     # => "foo&bar&0"
  #
  # The elements of an Array-like +enum+ may be mixture:
  #
  #   Gem::URI.encode_www_form([['foo', 0], ['bar', 1, 2], ['baz'], :bat])
  #   # => "foo=0&bar=1&baz&bat"
  #
  # When +enum+ is Hash-like,
  # each +key+/+value+ pair is converted to one or more fields:
  #
  # - If +value+ is
  #   {Array-convertible}[rdoc-ref:implicit_conversion.rdoc@Array-Convertible+Objects],
  #   each element +ele+ in +value+ is paired with +key+ to form a field:
  #
  #     name = Gem::URI.encode_www_form_component(key, enc)
  #     value = Gem::URI.encode_www_form_component(ele, enc)
  #     "#{name}=#{value}"
  #
  #   Example:
  #
  #     Gem::URI.encode_www_form({foo: [:bar, 1], baz: [:bat, :bam, 2]})
  #     # => "foo=bar&foo=1&baz=bat&baz=bam&baz=2"
  #
  # - Otherwise, +key+ and +value+ are paired to form a field:
  #
  #     name = Gem::URI.encode_www_form_component(key, enc)
  #     value = Gem::URI.encode_www_form_component(value, enc)
  #     "#{name}=#{value}"
  #
  #   Example:
  #
  #     Gem::URI.encode_www_form({foo: 0, bar: 1, baz: 2})
  #     # => "foo=0&bar=1&baz=2"
  #
  # The elements of a Hash-like +enum+ may be mixture:
  #
  #   Gem::URI.encode_www_form({foo: [0, 1], bar: 2})
  #   # => "foo=0&foo=1&bar=2"
  #
  def self.encode_www_form(enum, enc=nil)
    enum.map do |k,v|
      if v.nil?
        encode_www_form_component(k, enc)
      elsif v.respond_to?(:to_ary)
        v.to_ary.map do |w|
          str = encode_www_form_component(k, enc)
          unless w.nil?
            str << '='
            str << encode_www_form_component(w, enc)
          end
        end.join('&')
      else
        str = encode_www_form_component(k, enc)
        str << '='
        str << encode_www_form_component(v, enc)
      end
    end.join('&')
  end

  # Returns name/value pairs derived from the given string +str+,
  # which must be an ASCII string.
  #
  # The method may be used to decode the body of Net::HTTPResponse object +res+
  # for which <tt>res['Content-Type']</tt> is <tt>'application/x-www-form-urlencoded'</tt>.
  #
  # The returned data is an array of 2-element subarrays;
  # each subarray is a name/value pair (both are strings).
  # Each returned string has encoding +enc+,
  # and has had invalid characters removed via
  # {String#scrub}[rdoc-ref:String#scrub].
  #
  # A simple example:
  #
  #   Gem::URI.decode_www_form('foo=0&bar=1&baz')
  #   # => [["foo", "0"], ["bar", "1"], ["baz", ""]]
  #
  # The returned strings have certain conversions,
  # similar to those performed in Gem::URI.decode_www_form_component:
  #
  #   Gem::URI.decode_www_form('f%23o=%2F&b-r=%24&b+z=%40')
  #   # => [["f#o", "/"], ["b-r", "$"], ["b z", "@"]]
  #
  # The given string may contain consecutive separators:
  #
  #   Gem::URI.decode_www_form('foo=0&&bar=1&&baz=2')
  #   # => [["foo", "0"], ["", ""], ["bar", "1"], ["", ""], ["baz", "2"]]
  #
  # A different separator may be specified:
  #
  #   Gem::URI.decode_www_form('foo=0--bar=1--baz', separator: '--')
  #   # => [["foo", "0"], ["bar", "1"], ["baz", ""]]
  #
  def self.decode_www_form(str, enc=Encoding::UTF_8, separator: '&', use__charset_: false, isindex: false)
    raise ArgumentError, "the input of #{self.name}.#{__method__} must be ASCII only string" unless str.ascii_only?
    ary = []
    return ary if str.empty?
    enc = Encoding.find(enc)
    str.b.each_line(separator) do |string|
      string.chomp!(separator)
      key, sep, val = string.partition('=')
      if isindex
        if sep.empty?
          val = key
          key = +''
        end
        isindex = false
      end

      if use__charset_ and key == '_charset_' and e = get_encoding(val)
        enc = e
        use__charset_ = false
      end

      key.gsub!(/\+|%\h\h/, TBLDECWWWCOMP_)
      if val
        val.gsub!(/\+|%\h\h/, TBLDECWWWCOMP_)
      else
        val = +''
      end

      ary << [key, val]
    end
    ary.each do |k, v|
      k.force_encoding(enc)
      k.scrub!
      v.force_encoding(enc)
      v.scrub!
    end
    ary
  end

  private
=begin command for WEB_ENCODINGS_
  curl https://encoding.spec.whatwg.org/encodings.json|
  ruby -rjson -e 'H={}
  h={
    "shift_jis"=>"Windows-31J",
    "euc-jp"=>"cp51932",
    "iso-2022-jp"=>"cp50221",
    "x-mac-cyrillic"=>"macCyrillic",
  }
  JSON($<.read).map{|x|x["encodings"]}.flatten.each{|x|
    Encoding.find(n=h.fetch(n=x["name"].downcase,n))rescue next
    x["labels"].each{|y|H[y]=n}
  }
  puts "{"
  H.each{|k,v|puts %[  #{k.dump}=>#{v.dump},]}
  puts "}"
'
=end
  WEB_ENCODINGS_ = {
    "unicode-1-1-utf-8"=>"utf-8",
    "utf-8"=>"utf-8",
    "utf8"=>"utf-8",
    "866"=>"ibm866",
    "cp866"=>"ibm866",
    "csibm866"=>"ibm866",
    "ibm866"=>"ibm866",
    "csisolatin2"=>"iso-8859-2",
    "iso-8859-2"=>"iso-8859-2",
    "iso-ir-101"=>"iso-8859-2",
    "iso8859-2"=>"iso-8859-2",
    "iso88592"=>"iso-8859-2",
    "iso_8859-2"=>"iso-8859-2",
    "iso_8859-2:1987"=>"iso-8859-2",
    "l2"=>"iso-8859-2",
    "latin2"=>"iso-8859-2",
    "csisolatin3"=>"iso-8859-3",
    "iso-8859-3"=>"iso-8859-3",
    "iso-ir-109"=>"iso-8859-3",
    "iso8859-3"=>"iso-8859-3",
    "iso88593"=>"iso-8859-3",
    "iso_8859-3"=>"iso-8859-3",
    "iso_8859-3:1988"=>"iso-8859-3",
    "l3"=>"iso-8859-3",
    "latin3"=>"iso-8859-3",
    "csisolatin4"=>"iso-8859-4",
    "iso-8859-4"=>"iso-8859-4",
    "iso-ir-110"=>"iso-8859-4",
    "iso8859-4"=>"iso-8859-4",
    "iso88594"=>"iso-8859-4",
    "iso_8859-4"=>"iso-8859-4",
    "iso_8859-4:1988"=>"iso-8859-4",
    "l4"=>"iso-8859-4",
    "latin4"=>"iso-8859-4",
    "csisolatincyrillic"=>"iso-8859-5",
    "cyrillic"=>"iso-8859-5",
    "iso-8859-5"=>"iso-8859-5",
    "iso-ir-144"=>"iso-8859-5",
    "iso8859-5"=>"iso-8859-5",
    "iso88595"=>"iso-8859-5",
    "iso_8859-5"=>"iso-8859-5",
    "iso_8859-5:1988"=>"iso-8859-5",
    "arabic"=>"iso-8859-6",
    "asmo-708"=>"iso-8859-6",
    "csiso88596e"=>"iso-8859-6",
    "csiso88596i"=>"iso-8859-6",
    "csisolatinarabic"=>"iso-8859-6",
    "ecma-114"=>"iso-8859-6",
    "iso-8859-6"=>"iso-8859-6",
    "iso-8859-6-e"=>"iso-8859-6",
    "iso-8859-6-i"=>"iso-8859-6",
    "iso-ir-127"=>"iso-8859-6",
    "iso8859-6"=>"iso-8859-6",
    "iso88596"=>"iso-8859-6",
    "iso_8859-6"=>"iso-8859-6",
    "iso_8859-6:1987"=>"iso-8859-6",
    "csisolatingreek"=>"iso-8859-7",
    "ecma-118"=>"iso-8859-7",
    "elot_928"=>"iso-8859-7",
    "greek"=>"iso-8859-7",
    "greek8"=>"iso-8859-7",
    "iso-8859-7"=>"iso-8859-7",
    "iso-ir-126"=>"iso-8859-7",
    "iso8859-7"=>"iso-8859-7",
    "iso88597"=>"iso-8859-7",
    "iso_8859-7"=>"iso-8859-7",
    "iso_8859-7:1987"=>"iso-8859-7",
    "sun_eu_greek"=>"iso-8859-7",
    "csiso88598e"=>"iso-8859-8",
    "csisolatinhebrew"=>"iso-8859-8",
    "hebrew"=>"iso-8859-8",
    "iso-8859-8"=>"iso-8859-8",
    "iso-8859-8-e"=>"iso-8859-8",
    "iso-ir-138"=>"iso-8859-8",
    "iso8859-8"=>"iso-8859-8",
    "iso88598"=>"iso-8859-8",
    "iso_8859-8"=>"iso-8859-8",
    "iso_8859-8:1988"=>"iso-8859-8",
    "visual"=>"iso-8859-8",
    "csisolatin6"=>"iso-8859-10",
    "iso-8859-10"=>"iso-8859-10",
    "iso-ir-157"=>"iso-8859-10",
    "iso8859-10"=>"iso-8859-10",
    "iso885910"=>"iso-8859-10",
    "l6"=>"iso-8859-10",
    "latin6"=>"iso-8859-10",
    "iso-8859-13"=>"iso-8859-13",
    "iso8859-13"=>"iso-8859-13",
    "iso885913"=>"iso-8859-13",
    "iso-8859-14"=>"iso-8859-14",
    "iso8859-14"=>"iso-8859-14",
    "iso885914"=>"iso-8859-14",
    "csisolatin9"=>"iso-8859-15",
    "iso-8859-15"=>"iso-8859-15",
    "iso8859-15"=>"iso-8859-15",
    "iso885915"=>"iso-8859-15",
    "iso_8859-15"=>"iso-8859-15",
    "l9"=>"iso-8859-15",
    "iso-8859-16"=>"iso-8859-16",
    "cskoi8r"=>"koi8-r",
    "koi"=>"koi8-r",
    "koi8"=>"koi8-r",
    "koi8-r"=>"koi8-r",
    "koi8_r"=>"koi8-r",
    "koi8-ru"=>"koi8-u",
    "koi8-u"=>"koi8-u",
    "dos-874"=>"windows-874",
    "iso-8859-11"=>"windows-874",
    "iso8859-11"=>"windows-874",
    "iso885911"=>"windows-874",
    "tis-620"=>"windows-874",
    "windows-874"=>"windows-874",
    "cp1250"=>"windows-1250",
    "windows-1250"=>"windows-1250",
    "x-cp1250"=>"windows-1250",
    "cp1251"=>"windows-1251",
    "windows-1251"=>"windows-1251",
    "x-cp1251"=>"windows-1251",
    "ansi_x3.4-1968"=>"windows-1252",
    "ascii"=>"windows-1252",
    "cp1252"=>"windows-1252",
    "cp819"=>"windows-1252",
    "csisolatin1"=>"windows-1252",
    "ibm819"=>"windows-1252",
    "iso-8859-1"=>"windows-1252",
    "iso-ir-100"=>"windows-1252",
    "iso8859-1"=>"windows-1252",
    "iso88591"=>"windows-1252",
    "iso_8859-1"=>"windows-1252",
    "iso_8859-1:1987"=>"windows-1252",
    "l1"=>"windows-1252",
    "latin1"=>"windows-1252",
    "us-ascii"=>"windows-1252",
    "windows-1252"=>"windows-1252",
    "x-cp1252"=>"windows-1252",
    "cp1253"=>"windows-1253",
    "windows-1253"=>"windows-1253",
    "x-cp1253"=>"windows-1253",
    "cp1254"=>"windows-1254",
    "csisolatin5"=>"windows-1254",
    "iso-8859-9"=>"windows-1254",
    "iso-ir-148"=>"windows-1254",
    "iso8859-9"=>"windows-1254",
    "iso88599"=>"windows-1254",
    "iso_8859-9"=>"windows-1254",
    "iso_8859-9:1989"=>"windows-1254",
    "l5"=>"windows-1254",
    "latin5"=>"windows-1254",
    "windows-1254"=>"windows-1254",
    "x-cp1254"=>"windows-1254",
    "cp1255"=>"windows-1255",
    "windows-1255"=>"windows-1255",
    "x-cp1255"=>"windows-1255",
    "cp1256"=>"windows-1256",
    "windows-1256"=>"windows-1256",
    "x-cp1256"=>"windows-1256",
    "cp1257"=>"windows-1257",
    "windows-1257"=>"windows-1257",
    "x-cp1257"=>"windows-1257",
    "cp1258"=>"windows-1258",
    "windows-1258"=>"windows-1258",
    "x-cp1258"=>"windows-1258",
    "x-mac-cyrillic"=>"macCyrillic",
    "x-mac-ukrainian"=>"macCyrillic",
    "chinese"=>"gbk",
    "csgb2312"=>"gbk",
    "csiso58gb231280"=>"gbk",
    "gb2312"=>"gbk",
    "gb_2312"=>"gbk",
    "gb_2312-80"=>"gbk",
    "gbk"=>"gbk",
    "iso-ir-58"=>"gbk",
    "x-gbk"=>"gbk",
    "gb18030"=>"gb18030",
    "big5"=>"big5",
    "big5-hkscs"=>"big5",
    "cn-big5"=>"big5",
    "csbig5"=>"big5",
    "x-x-big5"=>"big5",
    "cseucpkdfmtjapanese"=>"cp51932",
    "euc-jp"=>"cp51932",
    "x-euc-jp"=>"cp51932",
    "csiso2022jp"=>"cp50221",
    "iso-2022-jp"=>"cp50221",
    "csshiftjis"=>"Windows-31J",
    "ms932"=>"Windows-31J",
    "ms_kanji"=>"Windows-31J",
    "shift-jis"=>"Windows-31J",
    "shift_jis"=>"Windows-31J",
    "sjis"=>"Windows-31J",
    "windows-31j"=>"Windows-31J",
    "x-sjis"=>"Windows-31J",
    "cseuckr"=>"euc-kr",
    "csksc56011987"=>"euc-kr",
    "euc-kr"=>"euc-kr",
    "iso-ir-149"=>"euc-kr",
    "korean"=>"euc-kr",
    "ks_c_5601-1987"=>"euc-kr",
    "ks_c_5601-1989"=>"euc-kr",
    "ksc5601"=>"euc-kr",
    "ksc_5601"=>"euc-kr",
    "windows-949"=>"euc-kr",
    "utf-16be"=>"utf-16be",
    "utf-16"=>"utf-16le",
    "utf-16le"=>"utf-16le",
  } # :nodoc:
  Ractor.make_shareable(WEB_ENCODINGS_) if defined?(Ractor)

  # :nodoc:
  # return encoding or nil
  # http://encoding.spec.whatwg.org/#concept-encoding-get
  def self.get_encoding(label)
    Encoding.find(WEB_ENCODINGS_[label.to_str.strip.downcase]) rescue nil
  end
end # module Gem::URI

module Gem

  #
  # Returns a \Gem::URI object derived from the given +uri+,
  # which may be a \Gem::URI string or an existing \Gem::URI object:
  #
  #   # Returns a new Gem::URI.
  #   uri = Gem::URI('http://github.com/ruby/ruby')
  #   # => #<Gem::URI::HTTP http://github.com/ruby/ruby>
  #   # Returns the given Gem::URI.
  #   Gem::URI(uri)
  #   # => #<Gem::URI::HTTP http://github.com/ruby/ruby>
  #
  def URI(uri)
    if uri.is_a?(Gem::URI::Generic)
      uri
    elsif uri = String.try_convert(uri)
      Gem::URI.parse(uri)
    else
      raise ArgumentError,
        "bad argument (expected Gem::URI object or Gem::URI string)"
    end
  end
  module_function :URI
end
