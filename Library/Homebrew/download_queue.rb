# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "downloadable"
require "concurrent/promises"
require "concurrent/executors"

module Homebrew
  class DownloadQueue
    sig { returns(Concurrent::FixedThreadPool) }
    attr_reader :pool
    private :pool

    sig { params(size: Integer).void }
    def initialize(size = 1)
      @pool = Concurrent::FixedThreadPool.new(size)
    end

    sig { params(downloadable: Downloadable, force: T::Boolean).returns(Concurrent::Promises::Future) }
    def enqueue(downloadable, force: false)
      quiet = pool.max_length > 1
      # Passing in arguments from outside into the future is a common `concurrent-ruby` pattern.
      # rubocop:disable Lint/ShadowingOuterLocalVariable
      Concurrent::Promises.future_on(pool, downloadable, force, quiet) do |downloadable, force, quiet|
        downloadable.clear_cache if force
        downloadable.fetch(quiet:)
      end
      # rubocop:enable Lint/ShadowingOuterLocalVariable
    end

    sig { void }
    def cancel
      # FIXME: Implement graceful cancellaction of running downloads based on
      #        https://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/Cancellation.html
      #        instead of killing the whole thread pool.
      pool.kill
    end

    sig { void }
    def shutdown
      pool.shutdown
      pool.wait_for_termination
    end
  end
end
