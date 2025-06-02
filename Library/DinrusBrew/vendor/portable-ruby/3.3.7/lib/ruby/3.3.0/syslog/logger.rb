# frozen_string_literal: false
require 'syslog'
require 'logger'

##
# Syslog::Logger is a Logger work-alike that logs via syslog instead of to a
# file.  You can use Syslog::Logger to aggregate logs between multiple
# machines.
#
# By default, Syslog::Logger uses the program name 'ruby', but this can be
# changed via the first argument to Syslog::Logger.new.
#
# NOTE! You can only set the Syslog::Logger program name when you initialize
# Syslog::Logger for the first time.  This is a limitation of the way
# Syslog::Logger uses syslog (and in some ways, a limitation of the way
# syslog(3) works).  Attempts to change Syslog::Logger's program name after
# the first initialization will be ignored.
#
# === Example
#
# The following will log to syslogd on your local machine:
#
#   require 'syslog/logger'
#
#   log = Syslog::Logger.new 'my_program'
#   log.info 'this line will be logged via syslog(3)'
#
# Also the facility may be set to specify the facility level which will be used:
#
#   log.info 'this line will be logged using Syslog default facility level'
#
#   log_local1 = Syslog::Logger.new 'my_program', Syslog::LOG_LOCAL1
#   log_local1.info 'this line will be logged using local1 facility level'
#
#
# You may need to perform some syslog.conf setup first.  For a BSD machine add
# the following lines to /etc/syslog.conf:
#
#  !my_program
#  *.*                                             /var/log/my_program.log
#
# Then touch /var/log/my_program.log and signal syslogd with a HUP
# (killall -HUP syslogd, on FreeBSD).
#
# If you wish to have logs automatically roll over and archive, see the
# newsyslog.conf(5) and newsyslog(8) man pages.

class Syslog::Logger
  # Default formatter for log messages.
  class Formatter
    def call severity, time, progname, msg
      clean msg
    end

    private

    ##
    # Clean up messages so they're nice and pretty.

    def clean message
      message = message.to_s.strip
      message.gsub!(/\e\[[0-9;]*m/, '') # remove useless ansi color codes
      return message
    end
  end

  ##
  # The version of Syslog::Logger you are using.

  VERSION = '2.1.0'

  ##
  # Maps Logger warning types to syslog(3) warning types.
  #
  # Messages from Ruby applications are not considered as critical as messages
  # from other system daemons using syslog(3), so most messages are reduced by
  # one level.  For example, a fatal message for Ruby's Logger is considered
  # an error for syslog(3).

  LEVEL_MAP = {
    ::Logger::UNKNOWN => Syslog::LOG_ALERT,
    ::Logger::FATAL   => Syslog::LOG_ERR,
    ::Logger::ERROR   => Syslog::LOG_WARNING,
    ::Logger::WARN    => Syslog::LOG_NOTICE,
    ::Logger::INFO    => Syslog::LOG_INFO,
    ::Logger::DEBUG   => Syslog::LOG_DEBUG,
  }

  ##
  # Returns the internal Syslog object that is initialized when the
  # first instance is created.

  def self.syslog
    @@syslog
  end

  ##
  # Specifies the internal Syslog object to be used.

  def self.syslog= syslog
    @@syslog = syslog
  end

  ##
  # Builds a methods for level +meth+.

  def self.make_methods meth
    level = ::Logger.const_get(meth.upcase)
    eval <<-EOM, nil, __FILE__, __LINE__ + 1
      def #{meth}(message = nil, &block)
        add(#{level}, message, &block)
      end

      def #{meth}?
        level <= #{level}
      end
    EOM
  end

  ##
  # :method: unknown
  #
  # Logs a +message+ at the unknown (syslog alert) log level, or logs the
  # message returned from the block.

  ##
  # :method: fatal
  #
  # Logs a +message+ at the fatal (syslog err) log level, or logs the message
  # returned from the block.

  ##
  # :method: error
  #
  # Logs a +message+ at the error (syslog warning) log level, or logs the
  # message returned from the block.

  ##
  # :method: warn
  #
  # Logs a +message+ at the warn (syslog notice) log level, or logs the
  # message returned from the block.

  ##
  # :method: info
  #
  # Logs a +message+ at the info (syslog info) log level, or logs the message
  # returned from the block.

  ##
  # :method: debug
  #
  # Logs a +message+ at the debug (syslog debug) log level, or logs the
  # message returned from the block.

  Logger::Severity::constants.each do |severity|
    make_methods severity.downcase
  end

  ##
  # Log level for Logger compatibility.

  attr_accessor :level

  # Logging formatter, as a +Proc+ that will take four arguments and
  # return the formatted message. The arguments are:
  #
  # +severity+:: The Severity of the log message.
  # +time+:: A Time instance representing when the message was logged.
  # +progname+:: The #progname configured, or passed to the logger method.
  # +msg+:: The _Object_ the user passed to the log message; not necessarily a
  #         String.
  #
  # The block should return an Object that can be written to the logging
  # device via +write+.  The default formatter is used when no formatter is
  # set.
  attr_accessor :formatter

  ##
  # The facility argument is used to specify what type of program is logging the message.

  attr_accessor :facility

  ##
  # Fills in variables for Logger compatibility.  If this is the first
  # instance of Syslog::Logger, +program_name+ may be set to change the logged
  # program name. The +facility+ may be set to specify the facility level which will be used.
  #
  # Due to the way syslog works, only one program name may be chosen.

  def initialize program_name = 'ruby', facility = nil
    @level = ::Logger::DEBUG
    @formatter = Formatter.new

    @@syslog ||= Syslog.open(program_name)

    @facility = (facility || @@syslog.facility)
  end

  ##
  # Almost duplicates Logger#add.  +progname+ is ignored.

  def add severity, message = nil, progname = nil, &block
    severity ||= ::Logger::UNKNOWN
    level <= severity and
      @@syslog.log( (LEVEL_MAP[severity] | @facility), '%s', formatter.call(severity, Time.now, progname, (message || block.call)) )
    true
  end
end
