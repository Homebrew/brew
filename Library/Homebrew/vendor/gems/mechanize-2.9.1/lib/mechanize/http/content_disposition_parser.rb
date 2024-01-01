# frozen_string_literal: true
# coding: BINARY

require 'strscan'
require 'time'

class Mechanize::HTTP
  ContentDisposition = Struct.new :type, :filename, :creation_date,
    :modification_date, :read_date, :size, :parameters
end

##
# Parser Content-Disposition headers that loosely follows RFC 2183.
#
# Beyond RFC 2183, this parser allows:
#
# * Missing disposition-type
# * Multiple semicolons
# * Whitespace around semicolons
# * Dates in ISO 8601 format

class Mechanize::HTTP::ContentDispositionParser

  attr_accessor :scanner # :nodoc:

  @parser = nil

  ##
  # Parses the disposition type and params in the +content_disposition+
  # string.  The "Content-Disposition:" must be removed.

  def self.parse content_disposition
    @parser ||= self.new
    @parser.parse content_disposition
  end

  ##
  # Creates a new parser Content-Disposition headers

  def initialize
    @scanner = nil
  end

  ##
  # Parses the +content_disposition+ header.  If +header+ is set to true the
  # "Content-Disposition:" portion will be parsed

  def parse content_disposition, header = false
    return nil if content_disposition.empty?

    @scanner = StringScanner.new content_disposition

    if header then
      return nil unless @scanner.scan(/Content-Disposition/i)
      return nil unless @scanner.scan(/:/)
      spaces
    end

    type = rfc_2045_token
    @scanner.scan(/;+/)

    if @scanner.peek(1) == '=' then
      @scanner.pos = 0
      type = nil
    end

    disposition = Mechanize::HTTP::ContentDisposition.new type

    spaces

    return nil unless parameters = parse_parameters

    disposition.filename          = parameters.delete 'filename'
    disposition.creation_date     = parameters.delete 'creation-date'
    disposition.modification_date = parameters.delete 'modification-date'
    disposition.read_date         = parameters.delete 'read-date'
    disposition.size              = parameters.delete 'size'
    disposition.parameters        = parameters

    disposition
  end

  ##
  # Extracts disposition-parm and returns a Hash.

  def parse_parameters
    parameters = {}

    while true do
      return nil unless param = rfc_2045_token
      param.downcase!
      return nil unless @scanner.scan(/=/)

      value = case param
              when /^filename$/ then
                rfc_2045_value
              when /^(creation|modification|read)-date$/ then
                date = rfc_2045_quoted_string

                begin
                  Time.rfc822 date
                rescue ArgumentError
                  begin
                    Time.iso8601 date
                  rescue ArgumentError
                    nil
                  end
                end
              when /^size$/ then
                rfc_2045_value.to_i(10)
              else
                rfc_2045_value
              end

      return nil unless value

      parameters[param] = value

      spaces

      break if @scanner.eos? or not @scanner.scan(/;+/)

      spaces
    end

    parameters
  end

  ##
  #   quoted-string = <"> *(qtext/quoted-pair) <">
  #   qtext         = <any CHAR excepting <">, "\" & CR,
  #                    and including linear-white-space
  #   quoted-pair   = "\" CHAR
  #
  # Parses an RFC 2045 quoted-string

  def rfc_2045_quoted_string
    return nil unless @scanner.scan(/"/)

    text = String.new

    while true do
      chunk = @scanner.scan(/[\000-\014\016-\041\043-\133\135-\177]+/) # not \r "

      if chunk then
        text << chunk

        if @scanner.peek(1) == '\\' then
          @scanner.get_byte
          return nil if @scanner.eos?
          text << @scanner.get_byte
        elsif @scanner.scan(/\r\n[\t ]+/) then
          text << " "
        end
      else
        if '\\"' == @scanner.peek(2) then
          @scanner.skip(/\\/)
          text << @scanner.get_byte
        elsif '"' == @scanner.peek(1) then
          @scanner.get_byte
          break
        else
          return nil
        end
      end
    end

    text
  end

  ##
  #   token := 1*<any (US-ASCII) CHAR except SPACE, CTLs, or tspecials>
  #
  # Parses an RFC 2045 token

  def rfc_2045_token
    @scanner.scan(/[^\000-\037\177()<>@,;:\\"\/\[\]?= ]+/)
  end

  ##
  #   value := token / quoted-string
  #
  # Parses an RFC 2045 value

  def rfc_2045_value
    if @scanner.peek(1) == '"' then
      rfc_2045_quoted_string
    else
      rfc_2045_token
    end
  end

  ##
  #   1*SP
  #
  # Parses spaces

  def spaces
    @scanner.scan(/ +/)
  end

end

