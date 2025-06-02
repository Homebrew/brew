# frozen_string_literal: true
# shareable_constant_value: literal

require 'date'

# :stopdoc:

# = time.rb
#
# When 'time' is required, Time is extended with additional methods for parsing
# and converting Times.
#
# == Features
#
# This library extends the Time class with the following conversions between
# date strings and Time objects:
#
# * date-time defined by {RFC 2822}[http://www.ietf.org/rfc/rfc2822.txt]
# * HTTP-date defined by {RFC 2616}[http://www.ietf.org/rfc/rfc2616.txt]
# * dateTime defined by XML Schema Part 2: Datatypes ({ISO
#   8601}[http://www.iso.org/iso/date_and_time_format])
# * various formats handled by Date._parse
# * custom formats handled by Date._strptime

# :startdoc:

class Time

  VERSION = "0.3.0"

  class << Time

    #
    # A hash of timezones mapped to hour differences from UTC. The
    # set of time zones corresponds to the ones specified by RFC 2822
    # and ISO 8601.
    #
    ZoneOffset = { # :nodoc:
      'UTC' => 0,
      # ISO 8601
      'Z' => 0,
      # RFC 822
      'UT' => 0, 'GMT' => 0,
      'EST' => -5, 'EDT' => -4,
      'CST' => -6, 'CDT' => -5,
      'MST' => -7, 'MDT' => -6,
      'PST' => -8, 'PDT' => -7,
      # Following definition of military zones is original one.
      # See RFC 1123 and RFC 2822 for the error in RFC 822.
      'A' => +1, 'B' => +2, 'C' => +3, 'D' => +4,  'E' => +5,  'F' => +6,
      'G' => +7, 'H' => +8, 'I' => +9, 'K' => +10, 'L' => +11, 'M' => +12,
      'N' => -1, 'O' => -2, 'P' => -3, 'Q' => -4,  'R' => -5,  'S' => -6,
      'T' => -7, 'U' => -8, 'V' => -9, 'W' => -10, 'X' => -11, 'Y' => -12,
    }

    #
    # Return the number of seconds the specified time zone differs
    # from UTC.
    #
    # Numeric time zones that include minutes, such as
    # <code>-10:00</code> or <code>+1330</code> will work, as will
    # simpler hour-only time zones like <code>-10</code> or
    # <code>+13</code>.
    #
    # Textual time zones listed in ZoneOffset are also supported.
    #
    # If the time zone does not match any of the above, +zone_offset+
    # will check if the local time zone (both with and without
    # potential Daylight Saving \Time changes being in effect) matches
    # +zone+. Specifying a value for +year+ will change the year used
    # to find the local time zone.
    #
    # If +zone_offset+ is unable to determine the offset, nil will be
    # returned.
    #
    #     require 'time'
    #
    #     Time.zone_offset("EST") #=> -18000
    #
    # You must require 'time' to use this method.
    #
    def zone_offset(zone, year=self.now.year)
      off = nil
      zone = zone.upcase
      if /\A([+-])(\d\d)(:?)(\d\d)(?:\3(\d\d))?\z/ =~ zone
        off = ($1 == '-' ? -1 : 1) * (($2.to_i * 60 + $4.to_i) * 60 + $5.to_i)
      elsif zone.match?(/\A[+-]\d\d\z/)
        off = zone.to_i * 3600
      elsif ZoneOffset.include?(zone)
        off = ZoneOffset[zone] * 3600
      elsif ((t = self.local(year, 1, 1)).zone.upcase == zone rescue false)
        off = t.utc_offset
      elsif ((t = self.local(year, 7, 1)).zone.upcase == zone rescue false)
        off = t.utc_offset
      end
      off
    end

    # :stopdoc:
    def zone_utc?(zone)
      # * +0000
      #   In RFC 2822, +0000 indicate a time zone at Universal Time.
      #   Europe/Lisbon is "a time zone at Universal Time" in Winter.
      #   Atlantic/Reykjavik is "a time zone at Universal Time".
      #   Africa/Dakar is "a time zone at Universal Time".
      #   So +0000 is a local time such as Europe/London, etc.
      # * GMT
      #   GMT is used as a time zone abbreviation in Europe/London,
      #   Africa/Dakar, etc.
      #   So it is a local time.
      #
      # * -0000, -00:00
      #   In RFC 2822, -0000 the date-time contains no information about the
      #   local time zone.
      #   In RFC 3339, -00:00 is used for the time in UTC is known,
      #   but the offset to local time is unknown.
      #   They are not appropriate for specific time zone such as
      #   Europe/London because time zone neutral,
      #   So -00:00 and -0000 are treated as UTC.
      zone.match?(/\A(?:-00:00|-0000|-00|UTC|Z|UT)\z/i)
    end
    private :zone_utc?

    def force_zone!(t, zone, offset=nil)
      if zone_utc?(zone)
        t.utc
      elsif offset ||= zone_offset(zone)
        # Prefer the local timezone over the fixed offset timezone because
        # the former is a real timezone and latter is an artificial timezone.
        t.localtime
        if t.utc_offset != offset
          # Use the fixed offset timezone only if the local timezone cannot
          # represent the given offset.
          t.localtime(offset)
        end
      else
        t.localtime
      end
    end
    private :force_zone!

    LeapYearMonthDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] # :nodoc:
    CommonYearMonthDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31] # :nodoc:
    def month_days(y, m)
      if ((y % 4 == 0) && (y % 100 != 0)) || (y % 400 == 0)
        LeapYearMonthDays[m-1]
      else
        CommonYearMonthDays[m-1]
      end
    end
    private :month_days

    def apply_offset(year, mon, day, hour, min, sec, off)
      if off < 0
        off = -off
        off, o = off.divmod(60)
        if o != 0 then sec += o; o, sec = sec.divmod(60); off += o end
        off, o = off.divmod(60)
        if o != 0 then min += o; o, min = min.divmod(60); off += o end
        off, o = off.divmod(24)
        if o != 0 then hour += o; o, hour = hour.divmod(24); off += o end
        if off != 0
          day += off
          days = month_days(year, mon)
          if days and days < day
            mon += 1
            if 12 < mon
              mon = 1
              year += 1
            end
            day = 1
          end
        end
      elsif 0 < off
        off, o = off.divmod(60)
        if o != 0 then sec -= o; o, sec = sec.divmod(60); off -= o end
        off, o = off.divmod(60)
        if o != 0 then min -= o; o, min = min.divmod(60); off -= o end
        off, o = off.divmod(24)
        if o != 0 then hour -= o; o, hour = hour.divmod(24); off -= o end
        if off != 0 then
          day -= off
          if day < 1
            mon -= 1
            if mon < 1
              year -= 1
              mon = 12
            end
            day = month_days(year, mon)
          end
        end
      end
      return year, mon, day, hour, min, sec
    end
    private :apply_offset

    def make_time(date, year, yday, mon, day, hour, min, sec, sec_fraction, zone, now)
      if !year && !yday && !mon && !day && !hour && !min && !sec && !sec_fraction
        raise ArgumentError, "no time information in #{date.inspect}"
      end

      off = nil
      if year || now
        off_year = year || now.year
        off = zone_offset(zone, off_year) if zone
      end

      if yday
        unless (1..366) === yday
          raise ArgumentError, "yday #{yday} out of range"
        end
        mon, day = (yday-1).divmod(31)
        mon += 1
        day += 1
        t = make_time(date, year, nil, mon, day, hour, min, sec, sec_fraction, zone, now)
        diff = yday - t.yday
        return t if diff.zero?
        day += diff
        if day > 28 and day > (mday = month_days(off_year, mon))
          if (mon += 1) > 12
            raise ArgumentError, "yday #{yday} out of range"
          end
          day -= mday
        end
        return make_time(date, year, nil, mon, day, hour, min, sec, sec_fraction, zone, now)
      end

      if now and now.respond_to?(:getlocal)
        if off
          now = now.getlocal(off) if now.utc_offset != off
        else
          now = now.getlocal
        end
      end

      usec = nil
      usec = sec_fraction * 1000000 if sec_fraction

      if now
        begin
          break if year; year = now.year
          break if mon; mon = now.mon
          break if day; day = now.day
          break if hour; hour = now.hour
          break if min; min = now.min
          break if sec; sec = now.sec
          break if sec_fraction; usec = now.tv_usec
        end until true
      end

      year ||= 1970
      mon ||= 1
      day ||= 1
      hour ||= 0
      min ||= 0
      sec ||= 0
      usec ||= 0

      if year != off_year
        off = nil
        off = zone_offset(zone, year) if zone
      end

      if off
        year, mon, day, hour, min, sec =
          apply_offset(year, mon, day, hour, min, sec, off)
        t = self.utc(year, mon, day, hour, min, sec, usec)
        force_zone!(t, zone, off)
        t
      else
        self.local(year, mon, day, hour, min, sec, usec)
      end
    end
    private :make_time
    # :startdoc:

    #
    # Takes a string representation of a Time and attempts to parse it
    # using a heuristic.
    #
    # This method **does not** function as a validator.  If the input
    # string does not match valid formats strictly, you may get a
    # cryptic result.  Should consider to use `Time.strptime` instead
    # of this method as possible.
    #
    #     require 'time'
    #
    #     Time.parse("2010-10-31") #=> 2010-10-31 00:00:00 -0500
    #
    # Any missing pieces of the date are inferred based on the current date.
    #
    #     require 'time'
    #
    #     # assuming the current date is "2011-10-31"
    #     Time.parse("12:00") #=> 2011-10-31 12:00:00 -0500
    #
    # We can change the date used to infer our missing elements by passing a second
    # object that responds to #mon, #day and #year, such as Date, Time or DateTime.
    # We can also use our own object.
    #
    #     require 'time'
    #
    #     class MyDate
    #       attr_reader :mon, :day, :year
    #
    #       def initialize(mon, day, year)
    #         @mon, @day, @year = mon, day, year
    #       end
    #     end
    #
    #     d  = Date.parse("2010-10-28")
    #     t  = Time.parse("2010-10-29")
    #     dt = DateTime.parse("2010-10-30")
    #     md = MyDate.new(10,31,2010)
    #
    #     Time.parse("12:00", d)  #=> 2010-10-28 12:00:00 -0500
    #     Time.parse("12:00", t)  #=> 2010-10-29 12:00:00 -0500
    #     Time.parse("12:00", dt) #=> 2010-10-30 12:00:00 -0500
    #     Time.parse("12:00", md) #=> 2010-10-31 12:00:00 -0500
    #
    # If a block is given, the year described in +date+ is converted
    # by the block.  This is specifically designed for handling two
    # digit years. For example, if you wanted to treat all two digit
    # years prior to 70 as the year 2000+ you could write this:
    #
    #     require 'time'
    #
    #     Time.parse("01-10-31") {|year| year + (year < 70 ? 2000 : 1900)}
    #     #=> 2001-10-31 00:00:00 -0500
    #     Time.parse("70-10-31") {|year| year + (year < 70 ? 2000 : 1900)}
    #     #=> 1970-10-31 00:00:00 -0500
    #
    # If the upper components of the given time are broken or missing, they are
    # supplied with those of +now+.  For the lower components, the minimum
    # values (1 or 0) are assumed if broken or missing.  For example:
    #
    #     require 'time'
    #
    #     # Suppose it is "Thu Nov 29 14:33:20 2001" now and
    #     # your time zone is EST which is GMT-5.
    #     now = Time.parse("Thu Nov 29 14:33:20 2001")
    #     Time.parse("16:30", now)     #=> 2001-11-29 16:30:00 -0500
    #     Time.parse("7/23", now)      #=> 2001-07-23 00:00:00 -0500
    #     Time.parse("Aug 31", now)    #=> 2001-08-31 00:00:00 -0500
    #     Time.parse("Aug 2000", now)  #=> 2000-08-01 00:00:00 -0500
    #
    # Since there are numerous conflicts among locally defined time zone
    # abbreviations all over the world, this method is not intended to
    # understand all of them.  For example, the abbreviation "CST" is
    # used variously as:
    #
    #     -06:00 in America/Chicago,
    #     -05:00 in America/Havana,
    #     +08:00 in Asia/Harbin,
    #     +09:30 in Australia/Darwin,
    #     +10:30 in Australia/Adelaide,
    #     etc.
    #
    # Based on this fact, this method only understands the time zone
    # abbreviations described in RFC 822 and the system time zone, in the
    # order named. (i.e. a definition in RFC 822 overrides the system
    # time zone definition.)  The system time zone is taken from
    # <tt>Time.local(year, 1, 1).zone</tt> and
    # <tt>Time.local(year, 7, 1).zone</tt>.
    # If the extracted time zone abbreviation does not match any of them,
    # it is ignored and the given time is regarded as a local time.
    #
    # ArgumentError is raised if Date._parse cannot extract information from
    # +date+ or if the Time class cannot represent specified date.
    #
    # This method can be used as a fail-safe for other parsing methods as:
    #
    #   Time.rfc2822(date) rescue Time.parse(date)
    #   Time.httpdate(date) rescue Time.parse(date)
    #   Time.xmlschema(date) rescue Time.parse(date)
    #
    # A failure of Time.parse should be checked, though.
    #
    # You must require 'time' to use this method.
    #
    def parse(date, now=self.now)
      comp = !block_given?
      d = Date._parse(date, comp)
      year = d[:year]
      year = yield(year) if year && !comp
      make_time(date, year, d[:yday], d[:mon], d[:mday], d[:hour], d[:min], d[:sec], d[:sec_fraction], d[:zone], now)
    end

    #
    # Works similar to +parse+ except that instead of using a
    # heuristic to detect the format of the input string, you provide
    # a second argument that describes the format of the string.
    #
    # If a block is given, the year described in +date+ is converted by the
    # block.  For example:
    #
    #   Time.strptime(...) {|y| y < 100 ? (y >= 69 ? y + 1900 : y + 2000) : y}
    #
    # Below is a list of the formatting options:
    #
    # %a :: The abbreviated weekday name ("Sun")
    # %A :: The  full  weekday  name ("Sunday")
    # %b :: The abbreviated month name ("Jan")
    # %B :: The  full  month  name ("January")
    # %c :: The preferred local date and time representation
    # %C :: Century (20 in 2009)
    # %d :: Day of the month (01..31)
    # %D :: Date (%m/%d/%y)
    # %e :: Day of the month, blank-padded ( 1..31)
    # %F :: Equivalent to %Y-%m-%d (the ISO 8601 date format)
    # %g :: The last two digits of the commercial year
    # %G :: The week-based year according to ISO-8601 (week 1 starts on Monday
    #       and includes January 4)
    # %h :: Equivalent to %b
    # %H :: Hour of the day, 24-hour clock (00..23)
    # %I :: Hour of the day, 12-hour clock (01..12)
    # %j :: Day of the year (001..366)
    # %k :: hour, 24-hour clock, blank-padded ( 0..23)
    # %l :: hour, 12-hour clock, blank-padded ( 0..12)
    # %L :: Millisecond of the second (000..999)
    # %m :: Month of the year (01..12)
    # %M :: Minute of the hour (00..59)
    # %n :: Newline (\n)
    # %N :: Fractional seconds digits
    # %p :: Meridian indicator ("AM" or "PM")
    # %P :: Meridian indicator ("am" or "pm")
    # %r :: time, 12-hour (same as %I:%M:%S %p)
    # %R :: time, 24-hour (%H:%M)
    # %s :: Number of seconds since 1970-01-01 00:00:00 UTC.
    # %S :: Second of the minute (00..60)
    # %t :: Tab character (\t)
    # %T :: time, 24-hour (%H:%M:%S)
    # %u :: Day of the week as a decimal, Monday being 1. (1..7)
    # %U :: Week number of the current year, starting with the first Sunday as
    #       the first day of the first week (00..53)
    # %v :: VMS date (%e-%b-%Y)
    # %V :: Week number of year according to ISO 8601 (01..53)
    # %W :: Week  number  of the current year, starting with the first Monday
    #       as the first day of the first week (00..53)
    # %w :: Day of the week (Sunday is 0, 0..6)
    # %x :: Preferred representation for the date alone, no time
    # %X :: Preferred representation for the time alone, no date
    # %y :: Year without a century (00..99)
    # %Y :: Year which may include century, if provided
    # %z :: Time zone as  hour offset from UTC (e.g. +0900)
    # %Z :: Time zone name
    # %% :: Literal "%" character
    # %+ :: date(1) (%a %b %e %H:%M:%S %Z %Y)
    #
    #     require 'time'
    #
    #     Time.strptime("2000-10-31", "%Y-%m-%d") #=> 2000-10-31 00:00:00 -0500
    #
    # You must require 'time' to use this method.
    #
    def strptime(date, format, now=self.now)
      d = Date._strptime(date, format)
      raise ArgumentError, "invalid date or strptime format - `#{date}' `#{format}'" unless d
      if seconds = d[:seconds]
        if sec_fraction = d[:sec_fraction]
          usec = sec_fraction * 1000000
          usec *= -1 if seconds < 0
        else
          usec = 0
        end
        t = Time.at(seconds, usec)
        if zone = d[:zone]
          force_zone!(t, zone)
        end
      else
        year = d[:year]
        year = yield(year) if year && block_given?
        yday = d[:yday]
        if (d[:cwyear] && !year) || ((d[:cwday] || d[:cweek]) && !(d[:mon] && d[:mday]))
          # make_time doesn't deal with cwyear/cwday/cweek
          return Date.strptime(date, format).to_time
        end
        if (d[:wnum0] || d[:wnum1]) && !yday && !(d[:mon] && d[:mday])
          yday = Date.strptime(date, format).yday
        end
        t = make_time(date, year, yday, d[:mon], d[:mday], d[:hour], d[:min], d[:sec], d[:sec_fraction], d[:zone], now)
      end
      t
    end

    MonthValue = { # :nodoc:
      'JAN' => 1, 'FEB' => 2, 'MAR' => 3, 'APR' => 4, 'MAY' => 5, 'JUN' => 6,
      'JUL' => 7, 'AUG' => 8, 'SEP' => 9, 'OCT' =>10, 'NOV' =>11, 'DEC' =>12
    }

    #
    # Parses +date+ as date-time defined by RFC 2822 and converts it to a Time
    # object.  The format is identical to the date format defined by RFC 822 and
    # updated by RFC 1123.
    #
    # ArgumentError is raised if +date+ is not compliant with RFC 2822
    # or if the Time class cannot represent specified date.
    #
    # See #rfc2822 for more information on this format.
    #
    #     require 'time'
    #
    #     Time.rfc2822("Wed, 05 Oct 2011 22:26:12 -0400")
    #     #=> 2010-10-05 22:26:12 -0400
    #
    # You must require 'time' to use this method.
    #
    def rfc2822(date)
      if /\A\s*
          (?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s*,\s*)?
          (\d{1,2})\s+
          (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+
          (\d{2,})\s+
          (\d{2})\s*
          :\s*(\d{2})
          (?:\s*:\s*(\d\d))?\s+
          ([+-]\d{4}|
           UT|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT|[A-IK-Z])/ix =~ date
        # Since RFC 2822 permit comments, the regexp has no right anchor.
        day = $1.to_i
        mon = MonthValue[$2.upcase]
        year = $3.to_i
        short_year_p = $3.length <= 3
        hour = $4.to_i
        min = $5.to_i
        sec = $6 ? $6.to_i : 0
        zone = $7

        if short_year_p
          # following year completion is compliant with RFC 2822.
          year = if year < 50
                   2000 + year
                 else
                   1900 + year
                 end
        end

        off = zone_offset(zone)
        year, mon, day, hour, min, sec =
          apply_offset(year, mon, day, hour, min, sec, off)
        t = self.utc(year, mon, day, hour, min, sec)
        force_zone!(t, zone, off)
        t
      else
        raise ArgumentError.new("not RFC 2822 compliant date: #{date.inspect}")
      end
    end
    alias rfc822 rfc2822

    #
    # Parses +date+ as an HTTP-date defined by RFC 2616 and converts it to a
    # Time object.
    #
    # ArgumentError is raised if +date+ is not compliant with RFC 2616 or if
    # the Time class cannot represent specified date.
    #
    # See #httpdate for more information on this format.
    #
    #     require 'time'
    #
    #     Time.httpdate("Thu, 06 Oct 2011 02:26:12 GMT")
    #     #=> 2011-10-06 02:26:12 UTC
    #
    # You must require 'time' to use this method.
    #
    def httpdate(date)
      if date.match?(/\A\s*
          (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun),\x20
          (\d{2})\x20
          (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\x20
          (\d{4})\x20
          (\d{2}):(\d{2}):(\d{2})\x20
          GMT
          \s*\z/ix)
        self.rfc2822(date).utc
      elsif /\A\s*
             (?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\x20
             (\d\d)-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d\d)\x20
             (\d\d):(\d\d):(\d\d)\x20
             GMT
             \s*\z/ix =~ date
        year = $3.to_i
        if year < 50
          year += 2000
        else
          year += 1900
        end
        self.utc(year, $2, $1.to_i, $4.to_i, $5.to_i, $6.to_i)
      elsif /\A\s*
             (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\x20
             (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\x20
             (\d\d|\x20\d)\x20
             (\d\d):(\d\d):(\d\d)\x20
             (\d{4})
             \s*\z/ix =~ date
        self.utc($6.to_i, MonthValue[$1.upcase], $2.to_i,
                 $3.to_i, $4.to_i, $5.to_i)
      else
        raise ArgumentError.new("not RFC 2616 compliant date: #{date.inspect}")
      end
    end

    #
    # Parses +time+ as a dateTime defined by the XML Schema and converts it to
    # a Time object.  The format is a restricted version of the format defined
    # by ISO 8601.
    #
    # ArgumentError is raised if +time+ is not compliant with the format or if
    # the Time class cannot represent the specified time.
    #
    # See #xmlschema for more information on this format.
    #
    #     require 'time'
    #
    #     Time.xmlschema("2011-10-05T22:26:12-04:00")
    #     #=> 2011-10-05 22:26:12-04:00
    #
    # You must require 'time' to use this method.
    #
    def xmlschema(time)
      if /\A\s*
          (-?\d+)-(\d\d)-(\d\d)
          T
          (\d\d):(\d\d):(\d\d)
          (\.\d+)?
          (Z|[+-]\d\d(?::?\d\d)?)?
          \s*\z/ix =~ time
        year = $1.to_i
        mon = $2.to_i
        day = $3.to_i
        hour = $4.to_i
        min = $5.to_i
        sec = $6.to_i
        usec = 0
        if $7
          usec = Rational($7) * 1000000
        end
        if $8
          zone = $8
          off = zone_offset(zone)
          year, mon, day, hour, min, sec =
            apply_offset(year, mon, day, hour, min, sec, off)
          t = self.utc(year, mon, day, hour, min, sec, usec)
          force_zone!(t, zone, off)
          t
        else
          self.local(year, mon, day, hour, min, sec, usec)
        end
      else
        raise ArgumentError.new("invalid xmlschema format: #{time.inspect}")
      end
    end
    alias iso8601 xmlschema
  end # class << self

  #
  # Returns a string which represents the time as date-time defined by RFC 2822:
  #
  #   day-of-week, DD month-name CCYY hh:mm:ss zone
  #
  # where zone is [+-]hhmm.
  #
  # If +self+ is a UTC time, -0000 is used as zone.
  #
  #     require 'time'
  #
  #     t = Time.now
  #     t.rfc2822  # => "Wed, 05 Oct 2011 22:26:12 -0400"
  #
  # You must require 'time' to use this method.
  #
  def rfc2822
    strftime('%a, %d %b %Y %T ') << (utc? ? '-0000' : strftime('%z'))
  end
  alias rfc822 rfc2822

  #
  # Returns a string which represents the time as RFC 1123 date of HTTP-date
  # defined by RFC 2616:
  #
  #   day-of-week, DD month-name CCYY hh:mm:ss GMT
  #
  # Note that the result is always UTC (GMT).
  #
  #     require 'time'
  #
  #     t = Time.now
  #     t.httpdate # => "Thu, 06 Oct 2011 02:26:12 GMT"
  #
  # You must require 'time' to use this method.
  #
  def httpdate
    getutc.strftime('%a, %d %b %Y %T GMT')
  end

  #
  # Returns a string which represents the time as a dateTime defined by XML
  # Schema:
  #
  #   CCYY-MM-DDThh:mm:ssTZD
  #   CCYY-MM-DDThh:mm:ss.sssTZD
  #
  # where TZD is Z or [+-]hh:mm.
  #
  # If self is a UTC time, Z is used as TZD.  [+-]hh:mm is used otherwise.
  #
  # +fraction_digits+ specifies a number of digits to use for fractional
  # seconds.  Its default value is 0.
  #
  #     require 'time'
  #
  #     t = Time.now
  #     t.iso8601  # => "2011-10-05T22:26:12-04:00"
  #
  # You must require 'time' to use this method.
  #
  def xmlschema(fraction_digits=0)
    fraction_digits = fraction_digits.to_i
    s = strftime("%FT%T")
    if fraction_digits > 0
      s << strftime(".%#{fraction_digits}N")
    end
    s << (utc? ? 'Z' : strftime("%:z"))
  end
  alias iso8601 xmlschema
end

