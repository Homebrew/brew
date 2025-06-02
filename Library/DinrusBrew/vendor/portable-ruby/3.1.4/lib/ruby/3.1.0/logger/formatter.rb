# frozen_string_literal: true

class Logger
  # Default formatter for log messages.
  class Formatter
    Format = "%s, [%s #%d] %5s -- %s: %s\n"
    DatetimeFormat = "%Y-%m-%dT%H:%M:%S.%6N"

    attr_accessor :datetime_format

    def initialize
      @datetime_format = nil
    end

    def call(severity, time, progname, msg)
      Format % [severity[0..0], format_datetime(time), Process.pid, severity, progname,
        msg2str(msg)]
    end

  private

    def format_datetime(time)
      time.strftime(@datetime_format || DatetimeFormat)
    end

    def msg2str(msg)
      case msg
      when ::String
        msg
      when ::Exception
        "#{ msg.message } (#{ msg.class })\n#{ msg.backtrace.join("\n") if msg.backtrace }"
      else
        msg.inspect
      end
    end
  end
end
