# frozen_string_literal: true

# This code was extracted from https://github.com/Solistra/ruby-digest which is under public domain
module Bundler
  module Digest
    # The initial constant values for the 32-bit constant words A, B, C, D, and
    # E, respectively.
    SHA1_WORDS = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0].freeze

    # The 8-bit field used for bitwise `AND` masking. Defaults to `0xFFFFFFFF`.
    SHA1_MASK = 0xFFFFFFFF

    class << self
      def sha1(string)
        unless string.is_a?(String)
          raise TypeError, "can't convert #{string.class.inspect} into String"
        end

        buffer = string.b

        words = SHA1_WORDS.dup
        generate_split_buffer(buffer) do |chunk|
          w = []
          chunk.each_slice(4) do |a, b, c, d|
            w << (((a << 8 | b) << 8 | c) << 8 | d)
          end
          a, b, c, d, e = *words
          (16..79).each do |i|
            w[i] = SHA1_MASK & rotate((w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]), 1)
          end
          0.upto(79) do |i|
            case i
            when  0..19
              f = ((b & c) | (~b & d))
              k = 0x5A827999
            when 20..39
              f = (b ^ c ^ d)
              k = 0x6ED9EBA1
            when 40..59
              f = ((b & c) | (b & d) | (c & d))
              k = 0x8F1BBCDC
            when 60..79
              f = (b ^ c ^ d)
              k = 0xCA62C1D6
            end
            t = SHA1_MASK & (SHA1_MASK & rotate(a, 5) + f + e + k + w[i])
            a, b, c, d, e = t, a, SHA1_MASK & rotate(b, 30), c, d # rubocop:disable Style/ParallelAssignment
          end
          mutated = [a, b, c, d, e]
          words.map!.with_index {|word, index| SHA1_MASK & (word + mutated[index]) }
        end

        words.pack("N*").unpack("H*").first
      end

      private

      def generate_split_buffer(string, &block)
        size   = string.bytesize * 8
        buffer = string.bytes << 128
        buffer << 0 while buffer.size % 64 != 56
        buffer.concat([size].pack("Q>").bytes)
        buffer.each_slice(64, &block)
      end

      def rotate(value, spaces)
        value << spaces | value >> (32 - spaces)
      end
    end
  end
end
