# typed: strong
# frozen_string_literal: true

module Utils
  module Timer
    sig { params(time: T.nilable(Time)).returns(T.any(Float, Integer, NilClass)) }
    def self.remaining(time)
      return unless time

      [0, time - Time.now].max
    end

    sig { params(time: T.nilable(Time)).returns(T.any(Float, Integer, NilClass)) }
    def self.remaining!(time)
      r = remaining(time)
      raise Timeout::Error if r && r <= 0

      r
    end
  end
end
