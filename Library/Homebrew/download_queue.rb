# typed: true
# frozen_string_literal: true

require "downloadable"
require "concurrent/promise"
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

    sig { params(downloadable: Downloadable).returns(Concurrent::Promise) }
    def enqueue(downloadable)
      Concurrent::Promise.execute(executor: pool) do
        downloadable.fetch(quiet: pool.max_length > 1)
      end
    end

    sig { void }
    def shutdown
      pool.shutdown
    end
  end
end
