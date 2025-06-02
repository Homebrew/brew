# frozen_string_literal: true
#--
# Copyright (c) 2001,2003 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.  You can redistribute and/or modify it under
# the same terms as Ruby.
#
# $Idaemons: /home/cvs/rb/abbrev.rb,v 1.2 2001/05/30 09:37:45 knu Exp $
# $RoughId: abbrev.rb,v 1.4 2003/10/14 19:45:42 knu Exp $
# $Id$
#++

##
# Calculates the set of unambiguous abbreviations for a given set of strings.
#
#   require 'abbrev'
#   require 'pp'
#
#   pp Abbrev.abbrev(['ruby'])
#   #=>  {"ruby"=>"ruby", "rub"=>"ruby", "ru"=>"ruby", "r"=>"ruby"}
#
#   pp Abbrev.abbrev(%w{ ruby rules })
#
# _Generates:_
#   { "ruby"  =>  "ruby",
#     "rub"   =>  "ruby",
#     "rules" =>  "rules",
#     "rule"  =>  "rules",
#     "rul"   =>  "rules" }
#
# It also provides an array core extension, Array#abbrev.
#
#   pp %w{ summer winter }.abbrev
#
# _Generates:_
#   { "summer"  => "summer",
#     "summe"   => "summer",
#     "summ"    => "summer",
#     "sum"     => "summer",
#     "su"      => "summer",
#     "s"       => "summer",
#     "winter"  => "winter",
#     "winte"   => "winter",
#     "wint"    => "winter",
#     "win"     => "winter",
#     "wi"      => "winter",
#     "w"       => "winter" }

module Abbrev

  # Given a set of strings, calculate the set of unambiguous abbreviations for
  # those strings, and return a hash where the keys are all the possible
  # abbreviations and the values are the full strings.
  #
  # Thus, given +words+ is "car" and "cone", the keys pointing to "car" would
  # be "ca" and "car", while those pointing to "cone" would be "co", "con", and
  # "cone".
  #
  #   require 'abbrev'
  #
  #   Abbrev.abbrev(%w{ car cone })
  #   #=> {"ca"=>"car", "con"=>"cone", "co"=>"cone", "car"=>"car", "cone"=>"cone"}
  #
  # The optional +pattern+ parameter is a pattern or a string. Only input
  # strings that match the pattern or start with the string are included in the
  # output hash.
  #
  #   Abbrev.abbrev(%w{car box cone crab}, /b/)
  #   #=> {"box"=>"box", "bo"=>"box", "b"=>"box", "crab" => "crab"}
  #
  #   Abbrev.abbrev(%w{car box cone}, 'ca')
  #   #=> {"car"=>"car", "ca"=>"car"}
  def abbrev(words, pattern = nil)
    table = {}
    seen = Hash.new(0)

    if pattern.is_a?(String)
      pattern = /\A#{Regexp.quote(pattern)}/  # regard as a prefix
    end

    words.each do |word|
      next if word.empty?
      word.size.downto(1) { |len|
        abbrev = word[0...len]

        next if pattern && pattern !~ abbrev

        case seen[abbrev] += 1
        when 1
          table[abbrev] = word
        when 2
          table.delete(abbrev)
        else
          break
        end
      }
    end

    words.each do |word|
      next if pattern && pattern !~ word

      table[word] = word
    end

    table
  end

  module_function :abbrev
end

class Array
  # Calculates the set of unambiguous abbreviations for the strings in +self+.
  #
  #   require 'abbrev'
  #   %w{ car cone }.abbrev
  #   #=> {"car"=>"car", "ca"=>"car", "cone"=>"cone", "con"=>"cone", "co"=>"cone"}
  #
  # The optional +pattern+ parameter is a pattern or a string. Only input
  # strings that match the pattern or start with the string are included in the
  # output hash.
  #
  #   %w{ fast boat day }.abbrev(/^.a/)
  #   #=> {"fast"=>"fast", "fas"=>"fast", "fa"=>"fast", "day"=>"day", "da"=>"day"}
  #
  #   Abbrev.abbrev(%w{car box cone}, "ca")
  #   #=> {"car"=>"car", "ca"=>"car"}
  #
  # See also Abbrev.abbrev
  def abbrev(pattern = nil)
    Abbrev::abbrev(self, pattern)
  end
end
