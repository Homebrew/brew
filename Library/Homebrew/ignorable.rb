# typed: strict
# frozen_string_literal: true

# Provides the ability to optionally ignore errors raised and continue execution.
module Ignorable
  # Marks exceptions which can be ignored and resumed from where they were raised.
  module ExceptionMixin; end

  # Runs the block in a Fiber whose `raise` pauses at the raise site and passes
  # the exception to `on_ignorable`. If it returns `:ignore`, execution resumes
  # after the raise site, otherwise the exception is raised there as usual.
  sig {
    type_parameters(:U)
      .params(
        on_ignorable: T.proc.params(exception: Exception).returns(Symbol),
        block:        T.proc.returns(T.type_parameter(:U)),
      )
      .returns(T.type_parameter(:U))
  }
  def self.hook_raise(on_ignorable:, &block)
    fiber = Fiber.new(&block)

    Object.class_eval do
      # `define_method` keeps Sorbet happy inside this `class_eval` block.
      define_method(:raise) do |*args, **kwargs|
        super(*args, **kwargs)
      # All possible exceptions must be pausable, not just `StandardError`.
      rescue Exception => e # rubocop:disable Lint/RescueException
        if e.is_a?(ScriptError) || Fiber.current != fiber
          super(e)
        else
          e.extend(ExceptionMixin)
          super(e) if Fiber.yield(e) != :ignore
        end
      end

      alias_method :fail, :raise
    end

    result = fiber.resume
    while fiber.alive?
      decision = begin
        on_ignorable.call(result)
      # Even `Interrupt` at the prompt must unwind the fiber, not abandon it.
      rescue Exception => e # rubocop:disable Lint/RescueException
        e
      end

      result = case decision
      when :ignore then fiber.resume(:ignore)
      # Raise inside the fiber so its `ensure` blocks and rescues still run.
      when Exception then fiber.raise(decision)
      else fiber.resume(:raise)
      end
    end
    result
  ensure
    Object.class_eval do
      remove_method(:raise)
      remove_method(:fail)
    end
  end
end
