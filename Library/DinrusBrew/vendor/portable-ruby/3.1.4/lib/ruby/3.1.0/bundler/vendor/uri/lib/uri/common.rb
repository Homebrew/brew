# frozen_string_literal: true
#--
# = uri/common.rb
#
# Author:: Akira Yamada <akira@ruby-lang.org>
# License::
#   You can redistribute it and/or modify it under the same term as Ruby.
#
# See Bundler::URI for general documentation
#

require_relative "rfc2396_parser"
require_relative "rfc3986_parser"

module Bundler::URI
  REGEXP = RFC2396_REGEXP
  Parser = RFC2396_Parser
  RFC3986_PARSER = RFC3986_Parser.new

  # Bundler::URI::Parser.new
  DEFAULT_PARSER = Parser.new
  DEFAULT_PARSER.pattern.each_pair do |sym, str|
    unless REGEXP::PATTERN.const_defined?(sym)
      REGEXP::PATTERN.const_set(sym, str)
    end
  end
  DEFAULT_PARSER.regexp.each_pair do |sym, str|
    const_set(sym, str)
  end

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

  include REGEXP

  @@schemes = {}
  # Returns a Hash of the defined schemes.
  def self.scheme_list
    @@schemes
  end

  #
  # Construct a Bundler::URI instance, using the scheme to detect the appropriate class
  # from +Bundler::URI.scheme_list+.
  #
  def self.for(scheme, *arguments, default: Generic)
    if scheme
      uri_class = @@schemes[scheme.upcase] || default
    else
      uri_class = default
    end

    return uri_class.new(scheme, *arguments)
  end

  #
  # Base class for all Bundler::URI exceptions.
  #
  class Error < StandardError; end
  #
  # Not a Bundler::URI.
  #
  class InvalidURIError < Error; end
  #
  # Not a Bundler::URI component.
  #
  class InvalidComponentError < Error; end
  #
  # Bundler::URI is valid, bad usage is not.
  #
  class BadURIError < Error; end

  #
  # == Synopsis
  #
  #   Bundler::URI::split(uri)
  #
  # == Args
  #
  # +uri+::
  #   String with Bundler::URI.
  #
  # == Description
  #
  # Splits the string on following parts and returns array with result:
  #
  # * Scheme
  # * Userinfo
  # * Host
  # * Port
  # * Registry
  # * Path
  # * Opaque
  # * Query
  # * Fragment
  #
  # == Usage
  #
  #   require 'bundler/vendor/uri/lib/uri'
  #
  #   Bundler::URI.split("http://www.ruby-lang.org/")
  #   # => ["http", nil, "www.ruby-lang.org", nil, nil, "/", nil, nil, nil]
  #
  def self.split(uri)
    RFC3986_PARSER.split(uri)
  end

  #
  # == Synopsis
  #
  #   Bundler::URI::parse(uri_str)
  #
  # == Args
  #
  # +uri_str+::
  #   String with Bundler::URI.
  #
  # == Description
  #
  # Creates one of the Bundler::URI's subclasses instance from the string.
  #
  # == Raises
  #
  # Bundler::URI::InvalidURIError::
  #   Raised if Bundler::URI given is not a correct one.
  #
  # == Usage
  #
  #   require 'bundler/vendor/uri/lib/uri'
  #
  #   uri = Bundler::URI.parse("http://www.ruby-lang.org/")
  #   # => #<Bundler::URI::HTTP http://www.ruby-lang.org/>
  #   uri.scheme
  #   # => "http"
  #   uri.host
  #   # => "www.ruby-lang.org"
  #
  # It's recommended to first ::escape the provided +uri_str+ if there are any
  # invalid Bundler::URI characters.
  #
  def self.parse(uri)
    RFC3986_PARSER.parse(uri)
  end

  #
  # == Synopsis
  #
  #   Bundler::URI::join(str[, str, ...])
  #
  # == Args
  #
  # +str+::
  #   String(s) to work with, will be converted to RFC3986 URIs before merging.
  #
  # == Description
  #
  # Joins URIs.
  #
  # == Usage
  #
  #   require 'bundler/vendor/uri/lib/uri'
  #
  #   Bundler::URI.join("http://example.com/","main.rbx")
  #   # => #<Bundler::URI::HTTP http://example.com/main.rbx>
  #
  #   Bundler::URI.join('http://example.com', 'foo')
  #   # => #<Bundler::URI::HTTP http://example.com/foo>
  #
  #   Bundler::URI.join('http://example.com', '/foo', '/bar')
  #   # => #<Bundler::URI::HTTP http://example.com/bar>
  #
  #   Bundler::URI.join('http://example.com', '/foo', 'bar')
  #   # => #<Bundler::URI::HTTP http://example.com/bar>
  #
  #   Bundler::URI.join('http://example.com', '/foo/', 'bar')
  #   # => #<Bundler::URI::HTTP http://example.com/foo/bar>
  #
  def self.join(*str)
    RFC3986_PARSER.join(*str)
  end

  #
  # == Synopsis
  #
  #   Bundler::URI::extract(str[, schemes][,&blk])
  #
  # == Args
  #
  # +str+::
  #   String to extract URIs from.
  # +schemes+::
  #   Limit Bundler::URI matching to specific schemes.
  #
  # == Description
  #
  # Extracts URIs from a string. If block given, iterates through all matched URIs.
  # Returns nil if block given or array with matches.
  #
  # == Usage
  #
  #   require "bundler/vendor/uri/lib/uri"
  #
  #   Bundler::URI.extract("text here http://foo.example.org/bla and here mailto:test@example.com and here also.")
  #   # => ["http://foo.example.com/bla", "mailto:test@example.com"]
  #
  def self.extract(str, schemes = nil, &block)
    warn "Bundler::URI.extract is obsolete", uplevel: 1 if $VERBOSE
    DEFAULT_PARSER.extract(str, schemes, &block)
  end

  #
  # == Synopsis
  #
  #   Bundler::URI::regexp([match_schemes])
  #
  # == Args
  #
  # +match_schemes+::
  #   Array of schemes. If given, resulting regexp matches to URIs
  #   whose scheme is one of the match_schemes.
  #
  # == Description
  #
  # Returns a Regexp object which matches to Bundler::URI-like strings.
  # The Regexp object returned by this method includes arbitrary
  # number of capture group (parentheses).  Never rely on its number.
  #
  # == Usage
  #
  #   require 'bundler/vendor/uri/lib/uri'
  #
  #   # extract first Bundler::URI from html_string
  #   html_string.slice(Bundler::URI.regexp)
  #
  #   # remove ftp URIs
  #   html_string.sub(Bundler::URI.regexp(['ftp']), '')
  #
  #   # You should not rely on the number of parentheses
  #   html_string.scan(Bundler::URI.regexp) do |*matches|
  #     p $&
  #   end
  #
  def self.regexp(schemes = nil)
    warn "Bundler::URI.regexp is obsolete", uplevel: 1 if $VERBOSE
    DEFAULT_PARSER.make_regexp(schemes)
  end

  TBLENCWWWCOMP_ = {} # :nodoc:
  256.times do |i|
    TBLENCWWWCOMP_[-i.chr] = -('%%%02X' % i)
  end
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

  # Encodes given +str+ to URL-encoded form data.
  #
  # This method doesn't convert *, -, ., 0-9, A-Z, _, a-z, but does convert SP
  # (ASCII space) to + and converts others to %XX.
  #
  # If +enc+ is given, convert +str+ to the encoding before percent encoding.
  #
  # This is an implementation of
  # https://www.w3.org/TR/2013/CR-html5-20130806/forms.html#url-encoded-form-data.
  #
  # See Bundler::URI.decode_www_form_component, Bundler::URI.encode_www_form.
  def self.encode_www_form_component(str, enc=nil)
    str = str.to_s.dup
    if str.encoding != Encoding::ASCII_8BIT
      if enc && enc != Encoding::ASCII_8BIT
        str.encode!(Encoding::UTF_8, invalid: :replace, undef: :replace)
        str.encode!(enc, fallback: ->(x){"&##{x.ord};"})
      end
      str.force_encoding(Encoding::ASCII_8BIT)
    end
    str.gsub!(/[^*\-.0-9A-Z_a-z]/, TBLENCWWWCOMP_)
    str.force_encoding(Encoding::US_ASCII)
  end

  # Decodes given +str+ of URL-encoded form data.
  #
  # This decodes + to SP.
  #
  # See Bundler::URI.encode_www_form_component, Bundler::URI.decode_www_form.
  def self.decode_www_form_component(str, enc=Encoding::UTF_8)
    raise ArgumentError, "invalid %-encoding (#{str})" if /%(?!\h\h)/ =~ str
    str.b.gsub(/\+|%\h\h/, TBLDECWWWCOMP_).force_encoding(enc)
  end

  # Generates URL-encoded form data from given +enum+.
  #
  # This generates application/x-www-form-urlencoded data defined in HTML5
  # from given an Enumerable object.
  #
  # This internally uses Bundler::URI.encode_www_form_component(str).
  #
  # This method doesn't convert the encoding of given items, so convert them
  # before calling this method if you want to send data as other than original
  # encoding or mixed encoding data. (Strings which are encoded in an HTML5
  # ASCII incompatible encoding are converted to UTF-8.)
  #
  # This method doesn't handle files.  When you send a file, use
  # multipart/form-data.
  #
  # This refers https://url.spec.whatwg.org/#concept-urlencoded-serializer
  #
  #    Bundler::URI.encode_www_form([["q", "ruby"], ["lang", "en"]])
  #    #=> "q=ruby&lang=en"
  #    Bundler::URI.encode_www_form("q" => "ruby", "lang" => "en")
  #    #=> "q=ruby&lang=en"
  #    Bundler::URI.encode_www_form("q" => ["ruby", "perl"], "lang" => "en")
  #    #=> "q=ruby&q=perl&lang=en"
  #    Bundler::URI.encode_www_form([["q", "ruby"], ["q", "perl"], ["lang", "en"]])
  #    #=> "q=ruby&q=perl&lang=en"
  #
  # See Bundler::URI.encode_www_form_component, Bundler::URI.decode_www_form.
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

  # Decodes URL-encoded form data from given +str+.
  #
  # This decodes application/x-www-form-urlencoded data
  # and returns an array of key-value arrays.
  #
  # This refers http://url.spec.whatwg.org/#concept-urlencoded-parser,
  # so this supports only &-separator, and doesn't support ;-separator.
  #
  #    ary = Bundler::URI.decode_www_form("a=1&a=2&b=3")
  #    ary                   #=> [['a', '1'], ['a', '2'], ['b', '3']]
  #    ary.assoc('a').last   #=> '1'
  #    ary.assoc('b').last   #=> '3'
  #    ary.rassoc('a').last  #=> '2'
  #    Hash[ary]             #=> {"a"=>"2", "b"=>"3"}
  #
  # See Bundler::URI.decode_www_form_component, Bundler::URI.encode_www_form.
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

  # :nodoc:
  # return encoding or nil
  # http://encoding.spec.whatwg.org/#concept-encoding-get
  def self.get_encoding(label)
    Encoding.find(WEB_ENCODINGS_[label.to_str.strip.downcase]) rescue nil
  end
end # module Bundler::URI

module Bundler

  #
  # Returns +uri+ converted to an Bundler::URI object.
  #
  def URI(uri)
    if uri.is_a?(Bundler::URI::Generic)
      uri
    elsif uri = String.try_convert(uri)
      Bundler::URI.parse(uri)
    else
      raise ArgumentError,
        "bad argument (expected Bundler::URI object or Bundler::URI string)"
    end
  end
  module_function :URI
end
