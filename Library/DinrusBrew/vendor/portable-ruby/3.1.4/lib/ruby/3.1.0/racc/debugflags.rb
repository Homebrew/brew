#--
#
#
#
# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the same terms of ruby.
# see the file "COPYING".
#
#++

module Racc

  class DebugFlags
    def DebugFlags.parse_option_string(s)
      parse = rule = token = state = la = prec = conf = false
      s.split(//).each do |ch|
        case ch
        when 'p' then parse = true
        when 'r' then rule = true
        when 't' then token = true
        when 's' then state = true
        when 'l' then la = true
        when 'c' then prec = true
        when 'o' then conf = true
        else
          raise "unknown debug flag char: #{ch.inspect}"
        end
      end
      new(parse, rule, token, state, la, prec, conf)
    end

    def initialize(parse = false, rule = false, token = false, state = false,
                   la = false, prec = false, conf = false)
      @parse = parse
      @rule = rule
      @token = token
      @state = state
      @la = la
      @prec = prec
      @any = (parse || rule || token || state || la || prec)
      @status_logging = conf
    end

    attr_reader :parse
    attr_reader :rule
    attr_reader :token
    attr_reader :state
    attr_reader :la
    attr_reader :prec

    def any?
      @any
    end

    attr_reader :status_logging
  end

end
