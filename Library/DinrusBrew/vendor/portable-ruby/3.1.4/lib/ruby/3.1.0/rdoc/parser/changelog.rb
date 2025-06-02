# frozen_string_literal: true

##
# A ChangeLog file parser.
#
# This parser converts a ChangeLog into an RDoc::Markup::Document.  When
# viewed as HTML a ChangeLog page will have an entry for each day's entries in
# the sidebar table of contents.
#
# This parser is meant to parse the MRI ChangeLog, but can be used to parse any
# {GNU style Change
# Log}[http://www.gnu.org/prep/standards/html_node/Style-of-Change-Logs.html].

class RDoc::Parser::ChangeLog < RDoc::Parser

  include RDoc::Parser::Text

  parse_files_matching(/(\/|\\|\A)ChangeLog[^\/\\]*\z/)

  ##
  # Attaches the +continuation+ of the previous line to the +entry_body+.
  #
  # Continued function listings are joined together as a single entry.
  # Continued descriptions are joined to make a single paragraph.

  def continue_entry_body entry_body, continuation
    return unless last = entry_body.last

    if last =~ /\)\s*\z/ and continuation =~ /\A\(/ then
      last.sub!(/\)\s*\z/, ',')
      continuation = continuation.sub(/\A\(/, '')
    end

    if last =~ /\s\z/ then
      last << continuation
    else
      last << ' ' + continuation
    end
  end

  ##
  # Creates an RDoc::Markup::Document given the +groups+ of ChangeLog entries.

  def create_document groups
    doc = RDoc::Markup::Document.new
    doc.omit_headings_below = 2
    doc.file = @top_level

    doc << RDoc::Markup::Heading.new(1, File.basename(@file_name))
    doc << RDoc::Markup::BlankLine.new

    groups.sort_by do |day,| day end.reverse_each do |day, entries|
      doc << RDoc::Markup::Heading.new(2, day.dup)
      doc << RDoc::Markup::BlankLine.new

      doc.concat create_entries entries
    end

    doc
  end

  ##
  # Returns a list of ChangeLog entries an RDoc::Markup nodes for the given
  # +entries+.

  def create_entries entries
    out = []

    entries.each do |entry, items|
      out << RDoc::Markup::Heading.new(3, entry)
      out << RDoc::Markup::BlankLine.new

      out << create_items(items)
    end

    out
  end

  ##
  # Returns an RDoc::Markup::List containing the given +items+ in the
  # ChangeLog

  def create_items items
    list = RDoc::Markup::List.new :NOTE

    items.each do |item|
      item =~ /\A(.*?(?:\([^)]+\))?):\s*/

      title = $1
      body = $'

      paragraph = RDoc::Markup::Paragraph.new body
      list_item = RDoc::Markup::ListItem.new title, paragraph
      list << list_item
    end

    list
  end

  ##
  # Groups +entries+ by date.

  def group_entries entries
    @time_cache ||= {}
    entries.group_by do |title, _|
      begin
        time = @time_cache[title]
        (time || parse_date(title)).strftime '%Y-%m-%d'
      rescue NoMethodError, ArgumentError
        time, = title.split '  ', 2
        parse_date(time).strftime '%Y-%m-%d'
      end
    end
  end

  ##
  # Parse date in ISO-8601, RFC-2822, or default of Git

  def parse_date(date)
    case date
    when /\A\s*(\d+)-(\d+)-(\d+)(?:[ T](\d+):(\d+):(\d+) *([-+]\d\d):?(\d\d))?\b/
      Time.new($1, $2, $3, $4, $5, $6, ("#{$7}:#{$8}" if $7))
    when /\A\s*\w{3}, +(\d+) (\w{3}) (\d+) (\d+):(\d+):(\d+) *(?:([-+]\d\d):?(\d\d))\b/
      Time.new($3, $2, $1, $4, $5, $6, ("#{$7}:#{$8}" if $7))
    when /\A\s*\w{3} (\w{3}) +(\d+) (\d+) (\d+):(\d+):(\d+) *(?:([-+]\d\d):?(\d\d))\b/
      Time.new($3, $1, $2, $4, $5, $6, ("#{$7}:#{$8}" if $7))
    when /\A\s*\w{3} (\w{3}) +(\d+) (\d+):(\d+):(\d+) (\d+)\b/
      Time.new($6, $1, $2, $3, $4, $5)
    else
      raise ArgumentError, "bad date: #{date}"
    end
  end

  ##
  # Parses the entries in the ChangeLog.
  #
  # Returns an Array of each ChangeLog entry in order of parsing.
  #
  # A ChangeLog entry is an Array containing the ChangeLog title (date and
  # committer) and an Array of ChangeLog items (file and function changed with
  # description).
  #
  # An example result would be:
  #
  #    [ 'Tue Dec  4 08:33:46 2012  Eric Hodel  <drbrain@segment7.net>',
  #      [ 'README.EXT:  Converted to RDoc format',
  #        'README.EXT.ja:  ditto']]

  def parse_entries
    @time_cache ||= {}

    if /\A((?:.*\n){,3})commit\s/ =~ @content
      class << self; prepend Git; end
      parse_info($1)
      return parse_entries
    end

    entries = []
    entry_name = nil
    entry_body = []

    @content.each_line do |line|
      case line
      when /^\s*$/ then
        next
      when /^\w.*/ then
        entries << [entry_name, entry_body] if entry_name

        entry_name = $&

        begin
          time = parse_date entry_name
          @time_cache[entry_name] = time
        rescue ArgumentError
          entry_name = nil
        end

        entry_body = []
      when /^(\t| {8})?\*\s*(.*)/ then # "\t* file.c (func): ..."
        entry_body << $2.dup
      when /^(\t| {8})?\s*(\(.*)/ then # "\t(func): ..."
        entry = $2

        if entry_body.last =~ /:/ then
          entry_body << entry.dup
        else
          continue_entry_body entry_body, entry
        end
      when /^(\t| {8})?\s*(.*)/ then
        continue_entry_body entry_body, $2
      end
    end

    entries << [entry_name, entry_body] if entry_name

    entries.reject! do |(entry,_)|
      entry == nil
    end

    entries
  end

  ##
  # Converts the ChangeLog into an RDoc::Markup::Document

  def scan
    @time_cache = {}

    entries = parse_entries
    grouped_entries = group_entries entries

    doc = create_document grouped_entries

    @top_level.comment = doc

    @top_level
  end

  module Git
    def parse_info(info)
      /^\s*base-url\s*=\s*(.*\S)/ =~ info
      @base_url = $1
    end

    def parse_entries
      entries = []

      @content.scan(/^commit\s+(\h{20})\h*\n((?:.+\n)*)\n((?: {4}.*\n+)*)/) do
        entry_name, header, entry_body = $1, $2, $3.gsub(/^ {4}/, '')
        # header = header.scan(/^ *(\S+?): +(.*)/).to_h
        # date = header["CommitDate"] || header["Date"]
        date = header[/^ *(?:Author)?Date: +(.*)/, 1]
        author = header[/^ *Author: +(.*)/, 1]
        begin
          time = parse_date(header[/^ *CommitDate: +(.*)/, 1] || date)
          @time_cache[entry_name] = time
          author.sub!(/\s*<(.*)>/, '')
          email = $1
          entries << [entry_name, [author, email, date, entry_body]]
        rescue ArgumentError
        end
      end

      entries
    end

    def create_entries entries
      # git log entries have no strictly itemized style like the old
      # style, just assume Markdown.
      entries.map do |commit, entry|
        LogEntry.new(@base_url, commit, *entry)
      end
    end

    LogEntry = Struct.new(:base, :commit, :author, :email, :date, :contents) do
      HEADING_LEVEL = 3

      def initialize(base, commit, author, email, date, contents)
        case contents
        when String
          contents = RDoc::Markdown.parse(contents).parts.each do |body|
            case body
            when RDoc::Markup::Heading
              body.level += HEADING_LEVEL + 1
            end
          end
          case first = contents[0]
          when RDoc::Markup::Paragraph
            contents[0] = RDoc::Markup::Heading.new(HEADING_LEVEL + 1, first.text)
          end
        end
        super
      end

      def level
        HEADING_LEVEL
      end

      def aref
        "label-#{commit}"
      end

      def label context = nil
        aref
      end

      def text
        case base
        when nil
          "#{date}"
        when /%s/
          "{#{date}}[#{base % commit}]"
        else
          "{#{date}}[#{base}#{commit}]"
        end + " {#{author}}[mailto:#{email}]"
      end

      def accept visitor
        visitor.accept_heading self
        begin
          if visitor.respond_to?(:code_object=)
            code_object = visitor.code_object
            visitor.code_object = self
          end
          contents.each do |body|
            body.accept visitor
          end
        ensure
          if visitor.respond_to?(:code_object)
            visitor.code_object = code_object
          end
        end
      end

      def pretty_print q # :nodoc:
        q.group(2, '[log_entry: ', ']') do
          q.text commit
          q.text ','
          q.breakable
          q.group(2, '[date: ', ']') { q.text date }
          q.text ','
          q.breakable
          q.group(2, '[author: ', ']') { q.text author }
          q.text ','
          q.breakable
          q.group(2, '[email: ', ']') { q.text email }
          q.text ','
          q.breakable
          q.pp contents
        end
      end
    end
  end
end

