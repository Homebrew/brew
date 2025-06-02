# frozen_string_literal: true

module Psych
  ###
  # Scan scalars for built in types
  class ScalarScanner
    # Taken from http://yaml.org/type/timestamp.html
    TIME = /^-?\d{4}-\d{1,2}-\d{1,2}(?:[Tt]|\s+)\d{1,2}:\d\d:\d\d(?:\.\d*)?(?:\s*(?:Z|[-+]\d{1,2}:?(?:\d\d)?))?$/

    # Taken from http://yaml.org/type/float.html
    # Base 60, [-+]inf and NaN are handled separately
    FLOAT = /^(?:[-+]?([0-9][0-9_,]*)?\.[0-9]*([eE][-+][0-9]+)?(?# base 10))$/x

    # Taken from http://yaml.org/type/int.html
    INTEGER_STRICT = /^(?:[-+]?0b[0-1_]+                  (?# base 2)
                         |[-+]?0[0-7_]+                   (?# base 8)
                         |[-+]?(0|[1-9][0-9_]*)           (?# base 10)
                         |[-+]?0x[0-9a-fA-F_]+            (?# base 16))$/x

    # Same as above, but allows commas.
    # Not to YML spec, but kept for backwards compatibility
    INTEGER_LEGACY = /^(?:[-+]?0b[0-1_,]+                        (?# base 2)
                         |[-+]?0[0-7_,]+                         (?# base 8)
                         |[-+]?(?:0|[1-9](?:[0-9]|,[0-9]|_[0-9])*) (?# base 10)
                         |[-+]?0x[0-9a-fA-F_,]+                  (?# base 16))$/x

    attr_reader :class_loader

    # Create a new scanner
    def initialize class_loader, strict_integer: false
      @symbol_cache = {}
      @class_loader = class_loader
      @strict_integer = strict_integer
    end

    # Tokenize +string+ returning the Ruby object
    def tokenize string
      return nil if string.empty?
      return @symbol_cache[string] if @symbol_cache.key?(string)
      integer_regex = @strict_integer ? INTEGER_STRICT : INTEGER_LEGACY
      # Check for a String type, being careful not to get caught by hash keys, hex values, and
      # special floats (e.g., -.inf).
      if string.match?(%r{^[^\d.:-]?[[:alpha:]_\s!@#$%\^&*(){}<>|/\\~;=]+}) || string.match?(/\n/)
        return string if string.length > 5

        if string.match?(/^[^ytonf~]/i)
          string
        elsif string == '~' || string.match?(/^null$/i)
          nil
        elsif string.match?(/^(yes|true|on)$/i)
          true
        elsif string.match?(/^(no|false|off)$/i)
          false
        else
          string
        end
      elsif string.match?(TIME)
        begin
          parse_time string
        rescue ArgumentError
          string
        end
      elsif string.match?(/^\d{4}-(?:1[012]|0\d|\d)-(?:[12]\d|3[01]|0\d|\d)$/)
        require 'date'
        begin
          class_loader.date.strptime(string, '%Y-%m-%d')
        rescue ArgumentError
          string
        end
      elsif string.match?(/^\+?\.inf$/i)
        Float::INFINITY
      elsif string.match?(/^-\.inf$/i)
        -Float::INFINITY
      elsif string.match?(/^\.nan$/i)
        Float::NAN
      elsif string.match?(/^:./)
        if string =~ /^:(["'])(.*)\1/
          @symbol_cache[string] = class_loader.symbolize($2.sub(/^:/, ''))
        else
          @symbol_cache[string] = class_loader.symbolize(string.sub(/^:/, ''))
        end
      elsif string.match?(/^[-+]?[0-9][0-9_]*(:[0-5]?[0-9]){1,2}$/)
        i = 0
        string.split(':').each_with_index do |n,e|
          i += (n.to_i * 60 ** (e - 2).abs)
        end
        i
      elsif string.match?(/^[-+]?[0-9][0-9_]*(:[0-5]?[0-9]){1,2}\.[0-9_]*$/)
        i = 0
        string.split(':').each_with_index do |n,e|
          i += (n.to_f * 60 ** (e - 2).abs)
        end
        i
      elsif string.match?(FLOAT)
        if string.match?(/\A[-+]?\.\Z/)
          string
        else
          Float(string.delete(',_').gsub(/\.([Ee]|$)/, '\1'))
        end
      elsif string.match?(integer_regex)
        parse_int string
      else
        string
      end
    end

    ###
    # Parse and return an int from +string+
    def parse_int string
      Integer(string.delete(',_'))
    end

    ###
    # Parse and return a Time from +string+
    def parse_time string
      klass = class_loader.load 'Time'

      date, time = *(string.split(/[ tT]/, 2))
      (yy, m, dd) = date.match(/^(-?\d{4})-(\d{1,2})-(\d{1,2})/).captures.map { |x| x.to_i }
      md = time.match(/(\d+:\d+:\d+)(?:\.(\d*))?\s*(Z|[-+]\d+(:\d\d)?)?/)

      (hh, mm, ss) = md[1].split(':').map { |x| x.to_i }
      us = (md[2] ? Rational("0.#{md[2]}") : 0) * 1000000

      time = klass.utc(yy, m, dd, hh, mm, ss, us)

      return time if 'Z' == md[3]
      return klass.at(time.to_i, us) unless md[3]

      tz = md[3].match(/^([+\-]?\d{1,2})\:?(\d{1,2})?$/)[1..-1].compact.map { |digit| Integer(digit, 10) }
      offset = tz.first * 3600

      if offset < 0
        offset -= ((tz[1] || 0) * 60)
      else
        offset += ((tz[1] || 0) * 60)
      end

      klass.new(yy, m, dd, hh, mm, ss+us/(1_000_000r), offset)
    end
  end
end
