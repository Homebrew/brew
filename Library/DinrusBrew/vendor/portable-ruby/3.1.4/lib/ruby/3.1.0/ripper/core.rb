# frozen_string_literal: true
#
# $Id$
#
# Copyright (c) 2003-2005 Minero Aoki
#
# This program is free software.
# You can distribute and/or modify this program under the Ruby License.
# For details of Ruby License, see ruby/COPYING.
#

require 'ripper.so'

class Ripper

  # Parses the given Ruby program read from +src+.
  # +src+ must be a String or an IO or a object with a #gets method.
  def Ripper.parse(src, filename = '(ripper)', lineno = 1)
    new(src, filename, lineno).parse
  end

  # This array contains name of parser events.
  PARSER_EVENTS = PARSER_EVENT_TABLE.keys

  # This array contains name of scanner events.
  SCANNER_EVENTS = SCANNER_EVENT_TABLE.keys

  # This array contains name of all ripper events.
  EVENTS = PARSER_EVENTS + SCANNER_EVENTS

  private

  # :stopdoc:
  def _dispatch_0() nil end
  def _dispatch_1(a) a end
  def _dispatch_2(a, b) a end
  def _dispatch_3(a, b, c) a end
  def _dispatch_4(a, b, c, d) a end
  def _dispatch_5(a, b, c, d, e) a end
  def _dispatch_6(a, b, c, d, e, f) a end
  def _dispatch_7(a, b, c, d, e, f, g) a end
  # :startdoc:

  #
  # Parser Events
  #

  PARSER_EVENT_TABLE.each do |id, arity|
    alias_method "on_#{id}", "_dispatch_#{arity}"
  end

  # This method is called when weak warning is produced by the parser.
  # +fmt+ and +args+ is printf style.
  def warn(fmt, *args)
  end

  # This method is called when strong warning is produced by the parser.
  # +fmt+ and +args+ is printf style.
  def warning(fmt, *args)
  end

  # This method is called when the parser found syntax error.
  def compile_error(msg)
  end

  #
  # Scanner Events
  #

  SCANNER_EVENTS.each do |id|
    alias_method "on_#{id}", :_dispatch_1
  end

end
