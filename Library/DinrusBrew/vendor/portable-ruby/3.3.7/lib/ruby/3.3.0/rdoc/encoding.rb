# coding: US-ASCII
# frozen_string_literal: true

##
# This class is a wrapper around File IO and Encoding that helps RDoc load
# files and convert them to the correct encoding.

module RDoc::Encoding

  HEADER_REGEXP = /^
    (?:
      \A\#!.*\n
      |
      ^\#\s+frozen[-_]string[-_]literal[=:].+\n
      |
      ^\#[^\n]+\b(?:en)?coding[=:]\s*(?<name>[^\s;]+).*\n
      |
      <\?xml[^?]*encoding=(?<quote>["'])(?<name>.*?)\k<quote>.*\n
    )+
  /xi # :nodoc:

  ##
  # Reads the contents of +filename+ and handles any encoding directives in
  # the file.
  #
  # The content will be converted to the +encoding+.  If the file cannot be
  # converted a warning will be printed and nil will be returned.
  #
  # If +force_transcode+ is true the document will be transcoded and any
  # unknown character in the target encoding will be replaced with '?'

  def self.read_file filename, encoding, force_transcode = false
    content = File.open filename, "rb" do |f| f.read end
    content.gsub!("\r\n", "\n") if RUBY_PLATFORM =~ /mswin|mingw/

    utf8 = content.sub!(/\A\xef\xbb\xbf/, '')

    enc = RDoc::Encoding.detect_encoding content
    content = RDoc::Encoding.change_encoding content, enc if enc

    begin
      encoding ||= Encoding.default_external
      orig_encoding = content.encoding

      if not orig_encoding.ascii_compatible? then
        content = content.encode encoding
      elsif utf8 then
        content = RDoc::Encoding.change_encoding content, Encoding::UTF_8
        content = content.encode encoding
      else
        # assume the content is in our output encoding
        content = RDoc::Encoding.change_encoding content, encoding
      end

      unless content.valid_encoding? then
        # revert and try to transcode
        content = RDoc::Encoding.change_encoding content, orig_encoding
        content = content.encode encoding
      end

      unless content.valid_encoding? then
        warn "unable to convert #{filename} to #{encoding}, skipping"
        content = nil
      end
    rescue Encoding::InvalidByteSequenceError,
           Encoding::UndefinedConversionError => e
      if force_transcode then
        content = RDoc::Encoding.change_encoding content, orig_encoding
        content = content.encode(encoding,
                                 :invalid => :replace,
                                 :undef => :replace,
                                 :replace => '?')
        return content
      else
        warn "unable to convert #{e.message} for #{filename}, skipping"
        return nil
      end
    end

    content
  rescue ArgumentError => e
    raise unless e.message =~ /unknown encoding name - (.*)/
    warn "unknown encoding name \"#{$1}\" for #{filename}, skipping"
    nil
  rescue Errno::EISDIR, Errno::ENOENT
    nil
  end

  ##
  # Detects the encoding of +string+ based on the magic comment

  def self.detect_encoding string
    result = HEADER_REGEXP.match string
    name = result && result[:name]

    name ? Encoding.find(name) : nil
  end

  ##
  # Removes magic comments and shebang

  def self.remove_magic_comment string
    string.sub HEADER_REGEXP do |s|
      s.gsub(/[^\n]/, '')
    end
  end

  ##
  # Changes encoding based on +encoding+ without converting and returns new
  # string

  def self.change_encoding text, encoding
    if text.kind_of? RDoc::Comment
      text.encode! encoding
    else
      String.new text, encoding: encoding
    end
  end

end
