# typed: true
# frozen_string_literal: true

require "monitor"

# Module for querying the current execution context.
module Context
  extend MonitorMixin

  def self.current=(context)
    synchronize do
      @current = context
    end
  end

  def self.current
    if (current_context = Thread.current[:context])
      return current_context
    end

    synchronize do
      @current ||= ContextStruct.new
    end
  end

  # Struct describing the current execution context.
  class ContextStruct
    def initialize(debug: nil, quiet: nil, verbose: nil)
      @debug = debug
      @quiet = quiet
      @verbose = verbose
    end

    sig { returns(T::Boolean) }
    def debug?
      @debug == true
    end

    sig { returns(T::Boolean) }
    def quiet?
      @quiet == true
    end

    sig { returns(T::Boolean) }
    def verbose?
      @verbose == true
    end
  end

  sig { returns(T::Boolean) }
  def debug?
    Context.current.debug?
  end

  sig { returns(T::Boolean) }
  def quiet?
    Context.current.quiet?
  end

  sig { returns(T::Boolean) }
  def verbose?
    Context.current.verbose?
  end

  def with_context(**options)
    old_context = Thread.current[:context]

    new_context = ContextStruct.new(
      debug:   options.fetch(:debug, old_context&.debug?),
      quiet:   options.fetch(:quiet, old_context&.quiet?),
      verbose: options.fetch(:verbose, old_context&.verbose?),
    )

    Thread.current[:context] = new_context

    begin
      yield
    ensure
      Thread.current[:context] = old_context
    end
  end
end
