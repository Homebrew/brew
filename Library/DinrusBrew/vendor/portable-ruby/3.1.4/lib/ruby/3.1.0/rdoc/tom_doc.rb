# frozen_string_literal: true
# :markup: tomdoc

# A parser for TomDoc based on TomDoc 1.0.0-rc1 (02adef9b5a)
#
# The TomDoc specification can be found at:
#
# http://tomdoc.org
#
# The latest version of the TomDoc specification can be found at:
#
# https://github.com/mojombo/tomdoc/blob/master/tomdoc.md
#
# To choose TomDoc as your only default format see RDoc::Options@Saved+Options
# for instructions on setting up a <code>.rdoc_options</code> file to store
# your project default.
#
# There are a few differences between this parser and the specification.  A
# best-effort was made to follow the specification as closely as possible but
# some choices to deviate were made.
#
# A future version of RDoc will warn when a MUST or MUST NOT is violated and
# may warn when a SHOULD or SHOULD NOT is violated.  RDoc will always try
# to emit documentation even if given invalid TomDoc.
#
# Here are some implementation choices this parser currently makes:
#
# This parser allows rdoc-style inline markup but you should not depended on
# it.
#
# This parser allows a space between the comment and the method body.
#
# This parser does not require the default value to be described for an
# optional argument.
#
# This parser does not examine the order of sections.  An Examples section may
# precede the Arguments section.
#
# This class is documented in TomDoc format.  Since this is a subclass of the
# RDoc markup parser there isn't much to see here, unfortunately.

class RDoc::TomDoc < RDoc::Markup::Parser

  # Internal: Token accessor

  attr_reader :tokens

  # Internal: Adds a post-processor which sets the RDoc section based on the
  # comment's status.
  #
  # Returns nothing.

  def self.add_post_processor # :nodoc:
    RDoc::Markup::PreProcess.post_process do |comment, code_object|
      next unless code_object and
                  RDoc::Comment === comment and comment.format == 'tomdoc'

      comment.text.gsub!(/(\A\s*# )(Public|Internal|Deprecated):\s+/) do
        section = code_object.add_section $2
        code_object.temporary_section = section

        $1
      end
    end
  end

  add_post_processor

  # Public: Parses TomDoc from text
  #
  # text - A String containing TomDoc-format text.
  #
  # Examples
  #
  #   RDoc::TomDoc.parse <<-TOMDOC
  #   This method does some things
  #
  #   Returns nothing.
  #   TOMDOC
  #   # => #<RDoc::Markup::Document:0xXXX @parts=[...], @file=nil>
  #
  # Returns an RDoc::Markup::Document representing the TomDoc format.

  def self.parse text
    parser = new

    parser.tokenize text
    doc = RDoc::Markup::Document.new
    parser.parse doc
    doc
  end

  # Internal: Extracts the Signature section's method signature
  #
  # comment - An RDoc::Comment that will be parsed and have the signature
  #           extracted
  #
  # Returns a String containing the signature and nil if not

  def self.signature comment
    return unless comment.tomdoc?

    document = comment.parse

    signature = nil
    found_heading = false
    found_signature = false

    document.parts.delete_if do |part|
      next false if found_signature

      found_heading ||=
        RDoc::Markup::Heading === part && part.text == 'Signature'

      next false unless found_heading

      next true if RDoc::Markup::BlankLine === part

      if RDoc::Markup::Verbatim === part then
        signature = part
        found_signature = true
      end
    end

    signature and signature.text
  end

  # Public: Creates a new TomDoc parser.  See also RDoc::Markup::parse

  def initialize
    super

    @section      = nil
    @seen_returns = false
  end

  # Internal: Builds a heading from the token stream
  #
  # level - The level of heading to create
  #
  # Returns an RDoc::Markup::Heading

  def build_heading level
    heading = super

    @section = heading.text

    heading
  end

  # Internal: Builds a verbatim from the token stream.  A verbatim in the
  # Examples section will be marked as in Ruby format.
  #
  # margin - The indentation from the margin for lines that belong to this
  #          verbatim section.
  #
  # Returns an RDoc::Markup::Verbatim

  def build_verbatim margin
    verbatim = super

    verbatim.format = :ruby if @section == 'Examples'

    verbatim
  end

  # Internal: Builds a paragraph from the token stream
  #
  # margin - Unused
  #
  # Returns an RDoc::Markup::Paragraph.

  def build_paragraph margin
    p :paragraph_start => margin if @debug

    paragraph = RDoc::Markup::Paragraph.new

    until @tokens.empty? do
      type, data, = get

      case type
      when :TEXT then
        @section = 'Returns' if data =~ /\A(Returns|Raises)/

        paragraph << data
      when :NEWLINE then
        if :TEXT == peek_token[0] then
          # Lines beginning with 'Raises' in the Returns section should not be
          # treated as multiline text
          if 'Returns' == @section and
            peek_token[1].start_with?('Raises') then
            break
          else
            paragraph << ' '
          end
        else
          break
        end
      else
        unget
        break
      end
    end

    p :paragraph_end => margin if @debug

    paragraph
  end

  ##
  # Detects a section change to "Returns" and adds a heading

  def parse_text parent, indent # :nodoc:
    paragraph = build_paragraph indent

    if false == @seen_returns and 'Returns' == @section then
      @seen_returns = true
      parent << RDoc::Markup::Heading.new(3, 'Returns')
      parent << RDoc::Markup::BlankLine.new
    end

    parent << paragraph
  end

  # Internal: Turns text into an Array of tokens
  #
  # text - A String containing TomDoc-format text.
  #
  # Returns self.

  def tokenize text
    text = text.sub(/\A(Public|Internal|Deprecated):\s+/, '')

    setup_scanner text

    until @s.eos? do
      pos = @s.pos

      # leading spaces will be reflected by the column of the next token
      # the only thing we loose are trailing spaces at the end of the file
      next if @s.scan(/ +/)

      @tokens << case
                 when @s.scan(/\r?\n/) then
                   token = [:NEWLINE, @s.matched, *pos]
                   @s.newline!
                   token
                 when @s.scan(/(Examples|Signature)$/) then
                   @tokens << [:HEADER, 3, *pos]

                   [:TEXT, @s[1], *pos]
                 when @s.scan(/([:\w][\w\[\]]*)[ ]+- /) then
                   [:NOTE, @s[1], *pos]
                 else
                   @s.scan(/.*/)
                   [:TEXT, @s.matched.sub(/\r$/, ''), *pos]
                 end
    end

    self
  end

end
