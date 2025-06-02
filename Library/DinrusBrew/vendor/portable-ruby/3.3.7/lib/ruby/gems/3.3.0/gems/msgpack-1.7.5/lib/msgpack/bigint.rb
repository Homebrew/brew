# frozen_string_literal: true

module MessagePack
  module Bigint
    # We split the bigint in 32bits chunks so that individual part fits into
    # a MRI immediate Integer.
    CHUNK_BITLENGTH = 32
    FORMAT = 'CL>*'

    if Integer.instance_method(:[]).arity != 1 # Ruby 2.7 and newer
      # Starting from Ruby 2.7 we can address arbitrary bitranges inside an Integer with Integer#[]
      # This allows to not allocate any Integer.
      def self.to_msgpack_ext(bigint)
        members = []

        if bigint < 0
          bigint = -bigint
          members << 1
        else
          members << 0
        end

        offset = 0
        length = bigint.bit_length
        while offset < length
          members << bigint[offset, CHUNK_BITLENGTH]
          offset += CHUNK_BITLENGTH
        end

        members.pack(FORMAT)
      end
    else
      # On 2.6 and older since we can't address arbitrary bitranges, so we fallback to shifting the bigint.
      # This means that after each shift, we may allocate another Integer instance.
      BASE = (2**CHUNK_BITLENGTH) - 1
      def self.to_msgpack_ext(bigint)
        members = []

        if bigint < 0
          bigint = -bigint
          members << 1
        else
          members << 0
        end

        while bigint > 0
          members << (bigint & BASE)
          bigint = bigint >> CHUNK_BITLENGTH
        end

        members.pack(FORMAT)
      end
    end

    def self.from_msgpack_ext(data)
      parts = data.unpack(FORMAT)

      sign = parts.shift
      sum = parts.pop.to_i

      parts.reverse_each do |part|
        sum = sum << CHUNK_BITLENGTH
        sum += part
      end

      sign == 0 ? sum : -sum
    end
  end
end
