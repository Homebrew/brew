# typed: strict
# frozen_string_literal: true

module Utils
  module Interrupts
    @mutex = T.let(Thread::Mutex.new, Thread::Mutex)

    sig { type_parameters(:U).params(_block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
    def self.ignore(&_block)
      @mutex.synchronize do
        interrupted = T.let(false, T::Boolean)
        old_sigint_handler = Signal.trap(:INT) do
          interrupted = true

          $stderr.print "\n"
          $stderr.puts "One sec, cleaning up..."
        end

        begin
          yield
        ensure
          Signal.trap(:INT, old_sigint_handler)

          Kernel.raise Interrupt if interrupted
        end
      end
    end
  end
end
