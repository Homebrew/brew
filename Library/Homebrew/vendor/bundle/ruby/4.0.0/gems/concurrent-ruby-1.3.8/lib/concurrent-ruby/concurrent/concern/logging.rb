require 'concurrent/atomic/atomic_reference'

module Concurrent
  module Concern

    # Include where logging is needed
    #
    # @!visibility private
    module Logging
      # The same as Logger::Severity but we copy it here to avoid a dependency on the logger gem just for these 7 constants
      DEBUG, INFO, WARN, ERROR, FATAL, UNKNOWN = 0, 1, 2, 3, 4, 5
      SEV_LABEL = %w[DEBUG INFO WARN ERROR FATAL ANY].freeze

      # Logs through {Concurrent.global_logger}, it can be overridden by setting @logger
      # @param [Integer] level one of Concurrent::Concern::Logging constants
      # @param [String] progname e.g. a path of an Actor
      # @param [String, nil] message when nil block is used to generate the message
      # @yieldreturn [String] a message
      def log(level, progname, message = nil, &block)
        logger = if defined?(@logger) && @logger
                   @logger
                 else
                   Concurrent.global_logger
                 end
        logger.call level, progname, message, &block
      rescue => error
        $stderr.puts "`Concurrent.global_logger` failed to log #{[level, progname, message, block]}\n" +
          "#{error.message} (#{error.class})\n#{error.backtrace.join "\n"}"
      end
    end
  end
end

module Concurrent
  extend Concern::Logging

  # Create a simple logger with provided level and output.
  def self.create_simple_logger(level = :FATAL, output = $stderr)
    level = Concern::Logging.const_get(level) unless level.is_a?(Integer)

    # TODO (pitr-ch 24-Dec-2016): figure out why it had to be replaced, stdlogger was deadlocking
    lambda do |severity, progname, message = nil, &block|
      return false if severity < level

      message           = block ? block.call : message
      formatted_message = case message
                          when String
                            message
                          when Exception
                            format "%s (%s)\n%s",
                                   message.message, message.class, (message.backtrace || []).join("\n")
                          else
                            message.inspect
                          end

      output.print format "[%s] %5s -- %s: %s\n",
                          Time.now.strftime('%Y-%m-%d %H:%M:%S.%L'),
                          Concern::Logging::SEV_LABEL[severity],
                          progname,
                          formatted_message
      true
    end
  end

  # Use logger created by #create_simple_logger to log concurrent-ruby messages.
  def self.use_simple_logger(level = :FATAL, output = $stderr)
    Concurrent.global_logger = create_simple_logger level, output
  end

  # Create a stdlib logger with provided level and output.
  # If you use this deprecated method you might need to add logger to your Gemfile to avoid warnings from Ruby 3.3.5+.
  # @deprecated
  def self.create_stdlib_logger(level = :FATAL, output = $stderr)
    require 'logger'
    logger           = Logger.new(output)
    logger.level     = level
    logger.formatter = lambda do |severity, datetime, progname, msg|
      formatted_message = case msg
                          when String
                            msg
                          when Exception
                            format "%s (%s)\n%s",
                                   msg.message, msg.class, (msg.backtrace || []).join("\n")
                          else
                            msg.inspect
                          end
      format "[%s] %5s -- %s: %s\n",
             datetime.strftime('%Y-%m-%d %H:%M:%S.%L'),
             severity,
             progname,
             formatted_message
    end

    lambda do |loglevel, progname, message = nil, &block|
      logger.add loglevel, message, progname, &block
    end
  end

  # Use logger created by #create_stdlib_logger to log concurrent-ruby messages.
  # @deprecated
  def self.use_stdlib_logger(level = :FATAL, output = $stderr)
    Concurrent.global_logger = create_stdlib_logger level, output
  end

  # TODO (pitr-ch 27-Dec-2016): remove deadlocking stdlib_logger methods

  # Suppresses all output when used for logging.
  NULL_LOGGER   = lambda { |level, progname, message = nil, &block| }

  # @!visibility private
  GLOBAL_LOGGER = AtomicReference.new(create_simple_logger(:WARN))
  private_constant :GLOBAL_LOGGER

  def self.global_logger
    GLOBAL_LOGGER.value
  end

  def self.global_logger=(value)
    GLOBAL_LOGGER.value = value
  end
end
