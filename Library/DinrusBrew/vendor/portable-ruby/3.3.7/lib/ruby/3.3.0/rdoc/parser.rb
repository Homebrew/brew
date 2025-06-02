# -*- coding: us-ascii -*-
# frozen_string_literal: true

##
# A parser is simple a class that subclasses RDoc::Parser and implements #scan
# to fill in an RDoc::TopLevel with parsed data.
#
# The initialize method takes an RDoc::TopLevel to fill with parsed content,
# the name of the file to be parsed, the content of the file, an RDoc::Options
# object and an RDoc::Stats object to inform the user of parsed items.  The
# scan method is then called to parse the file and must return the
# RDoc::TopLevel object.  By calling super these items will be set for you.
#
# In order to be used by RDoc the parser needs to register the file extensions
# it can parse.  Use ::parse_files_matching to register extensions.
#
#   require 'rdoc'
#
#   class RDoc::Parser::Xyz < RDoc::Parser
#     parse_files_matching /\.xyz$/
#
#     def initialize top_level, file_name, content, options, stats
#       super
#
#       # extra initialization if needed
#     end
#
#     def scan
#       # parse file and fill in @top_level
#     end
#   end

class RDoc::Parser

  @parsers = []

  class << self

    ##
    # An Array of arrays that maps file extension (or name) regular
    # expressions to parser classes that will parse matching filenames.
    #
    # Use parse_files_matching to register a parser's file extensions.

    attr_reader :parsers

  end

  ##
  # The name of the file being parsed

  attr_reader :file_name

  ##
  # Alias an extension to another extension. After this call, files ending
  # "new_ext" will be parsed using the same parser as "old_ext"

  def self.alias_extension(old_ext, new_ext)
    old_ext = old_ext.sub(/^\.(.*)/, '\1')
    new_ext = new_ext.sub(/^\.(.*)/, '\1')

    parser = can_parse_by_name "xxx.#{old_ext}"
    return false unless parser

    RDoc::Parser.parsers.unshift [/\.#{new_ext}$/, parser]

    true
  end

  ##
  # Determines if the file is a "binary" file which basically means it has
  # content that an RDoc parser shouldn't try to consume.

  def self.binary?(file)
    return false if file =~ /\.(rdoc|txt)$/

    s = File.read(file, 1024) or return false

    return true if s[0, 2] == Marshal.dump('')[0, 2] or s.index("\x00")

    mode = 'r:utf-8' # default source encoding has been changed to utf-8
    s.sub!(/\A#!.*\n/, '')     # assume shebang line isn't longer than 1024.
    encoding = s[/^\s*\#\s*(?:-\*-\s*)?(?:en)?coding:\s*([^\s;]+?)(?:-\*-|[\s;])/, 1]
    mode = "rb:#{encoding}" if encoding
    s = File.open(file, mode) {|f| f.gets(nil, 1024)}

    not s.valid_encoding?
  end

  ##
  # Checks if +file+ is a zip file in disguise.  Signatures from
  # http://www.garykessler.net/library/file_sigs.html

  def self.zip? file
    zip_signature = File.read file, 4

    zip_signature == "PK\x03\x04" or
      zip_signature == "PK\x05\x06" or
      zip_signature == "PK\x07\x08"
  rescue
    false
  end

  ##
  # Return a parser that can handle a particular extension

  def self.can_parse file_name
    parser = can_parse_by_name file_name

    # HACK Selenium hides a jar file using a .txt extension
    return if parser == RDoc::Parser::Simple and zip? file_name

    parser
  end

  ##
  # Returns a parser that can handle the extension for +file_name+.  This does
  # not depend upon the file being readable.

  def self.can_parse_by_name file_name
    _, parser = RDoc::Parser.parsers.find { |regexp,| regexp =~ file_name }

    # The default parser must not parse binary files
    ext_name = File.extname file_name
    return parser if ext_name.empty?

    if parser == RDoc::Parser::Simple and ext_name !~ /txt|rdoc/ then
      case check_modeline file_name
      when nil, 'rdoc' then # continue
      else return nil
      end
    end

    parser
  rescue Errno::EACCES
  end

  ##
  # Returns the file type from the modeline in +file_name+

  def self.check_modeline file_name
    line = File.open file_name do |io|
      io.gets
    end

    /-\*-\s*(.*?\S)\s*-\*-/ =~ line

    return nil unless type = $1

    if /;/ =~ type then
      return nil unless /(?:\s|\A)mode:\s*([^\s;]+)/i =~ type
      type = $1
    end

    return nil if /coding:/i =~ type

    type.downcase
  rescue ArgumentError
  rescue Encoding::InvalidByteSequenceError # invalid byte sequence

  end

  ##
  # Finds and instantiates the correct parser for the given +file_name+ and
  # +content+.

  def self.for top_level, file_name, content, options, stats
    return if binary? file_name

    parser = use_markup content

    unless parser then
      parse_name = file_name

      # If no extension, look for shebang
      if file_name !~ /\.\w+$/ && content =~ %r{\A#!(.+)} then
        shebang = $1
        case shebang
        when %r{env\s+ruby}, %r{/ruby}
          parse_name = 'dummy.rb'
        end
      end

      parser = can_parse parse_name
    end

    return unless parser

    content = remove_modeline content

    parser.new top_level, file_name, content, options, stats
  rescue SystemCallError
    nil
  end

  ##
  # Record which file types this parser can understand.
  #
  # It is ok to call this multiple times.

  def self.parse_files_matching(regexp)
    RDoc::Parser.parsers.unshift [regexp, self]
  end

  ##
  # Removes an emacs-style modeline from the first line of the document

  def self.remove_modeline content
    content.sub(/\A.*-\*-\s*(.*?\S)\s*-\*-.*\r?\n/, '')
  end

  ##
  # If there is a <tt>markup: parser_name</tt> comment at the front of the
  # file, use it to determine the parser.  For example:
  #
  #   # markup: rdoc
  #   # Class comment can go here
  #
  #   class C
  #   end
  #
  # The comment should appear as the first line of the +content+.
  #
  # If the content contains a shebang or editor modeline the comment may
  # appear on the second or third line.
  #
  # Any comment style may be used to hide the markup comment.

  def self.use_markup content
    markup = content.lines.first(3).grep(/markup:\s+(\w+)/) { $1 }.first

    return unless markup

    # TODO Ruby should be returned only when the filename is correct
    return RDoc::Parser::Ruby if %w[tomdoc markdown].include? markup

    markup = Regexp.escape markup

    _, selected = RDoc::Parser.parsers.find do |_, parser|
      /^#{markup}$/i =~ parser.name.sub(/.*:/, '')
    end

    selected
  end

  ##
  # Creates a new Parser storing +top_level+, +file_name+, +content+,
  # +options+ and +stats+ in instance variables.  In +@preprocess+ an
  # RDoc::Markup::PreProcess object is created which allows processing of
  # directives.

  def initialize top_level, file_name, content, options, stats
    @top_level = top_level
    @top_level.parser = self.class
    @store = @top_level.store

    @file_name = file_name
    @content = content
    @options = options
    @stats = stats

    @preprocess = RDoc::Markup::PreProcess.new @file_name, @options.rdoc_include
    @preprocess.options = @options
  end

  autoload :RubyTools, "#{__dir__}/parser/ruby_tools"
  autoload :Text,      "#{__dir__}/parser/text"

  ##
  # Normalizes tabs in +body+

  def handle_tab_width(body)
    if /\t/ =~ body
      tab_width = @options.tab_width
      body.split(/\n/).map do |line|
        1 while line.gsub!(/\t+/) do
          b, e = $~.offset(0)
          ' ' * (tab_width * (e-b) - b % tab_width)
        end
        line
      end.join "\n"
    else
      body
    end
  end
end

# simple must come first in order to show up last in the parsers list
require_relative 'parser/simple'
require_relative 'parser/c'
require_relative 'parser/changelog'
require_relative 'parser/markdown'
require_relative 'parser/rd'
require_relative 'parser/ruby'
