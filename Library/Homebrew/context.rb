# typed: strict
# frozen_string_literal: true

require "monitor"

# Module for querying the current execution context.
module Context
  extend MonitorMixin

  # Struct describing the current execution context.
  class ContextStruct
    sig { params(debug: T.nilable(T::Boolean), quiet: T.nilable(T::Boolean), verbose: T.nilable(T::Boolean)).void }
    def initialize(debug: nil, quiet: nil, verbose: nil)
      @debug = T.let(debug, T.nilable(T::Boolean))
      @quiet = T.let(quiet, T.nilable(T::Boolean))
      @verbose = T.let(verbose, T.nilable(T::Boolean))
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

  @current = T.let(nil, T.nilable(ContextStruct))

  sig { params(context: ContextStruct).void }
  def self.current=(context)
    synchronize do
      @current = context
    end
  end

  sig { returns(ContextStruct) }
  def self.current
    current_context = T.cast(Thread.current[:context], T.nilable(ContextStruct))
    return current_context if current_context

    synchronize do
      current = T.let(@current, T.nilable(ContextStruct))
      current ||= ContextStruct.new
      @current = current
      current
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

  sig {
    params(debug: T.nilable(T::Boolean), quiet: T.nilable(T::Boolean), verbose: T.nilable(T::Boolean),
           _block: T.proc.void).returns(T.untyped)
  }
  def with_context(debug: debug?, quiet: quiet?, verbose: verbose?, &_block)
    old_context = Context.current
    Thread.current[:context] = ContextStruct.new(debug:, quiet:, verbose:)

    begin
      yield
    ensure
      Thread.current[:context] = old_context
    end
  end
end
