# typed: strict
# frozen_string_literal: true

require "monitor"

# Module for querying the current execution context.
module Context
  extend MonitorMixin

  # Struct describing the current execution context.
  class ContextStruct
    sig {
      params(
        debug:                          T::Boolean,
        quiet:                          T::Boolean,
        verbose:                        T::Boolean,
        deferred_environment_expansion: T::Boolean,
      ).void
    }
    def initialize(debug: false, quiet: false, verbose: false, deferred_environment_expansion: false)
      @debug = debug
      @quiet = quiet
      @verbose = verbose
      @deferred_environment_expansion = deferred_environment_expansion
    end

    sig { returns(T::Boolean) }
    def debug?
      @debug
    end

    sig { returns(T::Boolean) }
    def quiet?
      @quiet
    end

    sig { returns(T::Boolean) }
    def verbose?
      @verbose
    end

    sig { returns(T::Boolean) }
    def deferred_environment_expansion?
      @deferred_environment_expansion
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

  sig { returns(T::Boolean) }
  def deferred_environment_expansion?
    Context.current.deferred_environment_expansion?
  end

  sig {
    params(
      debug:                          T::Boolean,
      quiet:                          T::Boolean,
      verbose:                        T::Boolean,
      deferred_environment_expansion: T::Boolean,
      _block:                         T.proc.void,
    ).returns(T.untyped)
  }
  def with_context(debug: debug?, quiet: quiet?, verbose: verbose?,
                   deferred_environment_expansion: deferred_environment_expansion?, &_block)
    old_context = Context.current
    Thread.current[:context] = ContextStruct.new(debug:, quiet:, verbose:, deferred_environment_expansion:)

    begin
      yield
    ensure
      Thread.current[:context] = old_context
    end
  end
end
