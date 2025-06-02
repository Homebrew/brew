# frozen_string_literal: true

module MessagePack
  class Timestamp # a.k.a. "TimeSpec"
    # Because the byte-order of MessagePack is big-endian in,
    # pack() and unpack() specifies ">".
    # See https://docs.ruby-lang.org/en/trunk/Array.html#method-i-pack for details.

    # The timestamp extension type defined in the MessagePack spec.
    # See https://github.com/msgpack/msgpack/blob/master/spec.md#timestamp-extension-type for details.
    TYPE = -1

    TIMESTAMP32_MAX_SEC = (1 << 32) - 1
    TIMESTAMP64_MAX_SEC = (1 << 34) - 1

    # @return [Integer]
    attr_reader :sec

    # @return [Integer]
    attr_reader :nsec

    # @param [Integer] sec
    # @param [Integer] nsec
    def initialize(sec, nsec)
      @sec = sec
      @nsec = nsec
    end

    def self.from_msgpack_ext(data)
      case data.length
      when 4
        # timestamp32 (sec: uint32be)
        sec, = data.unpack('L>')
        new(sec, 0)
      when 8
        # timestamp64 (nsec: uint30be, sec: uint34be)
        n, s = data.unpack('L>2')
        sec = ((n & 0b11) << 32) | s
        nsec = n >> 2
        new(sec, nsec)
      when 12
        # timestam96 (nsec: uint32be, sec: int64be)
        nsec, sec = data.unpack('L>q>')
        new(sec, nsec)
      else
        raise MalformedFormatError, "Invalid timestamp data size: #{data.length}"
      end
    end

    def self.to_msgpack_ext(sec, nsec)
      if sec >= 0 && nsec >= 0 && sec <= TIMESTAMP64_MAX_SEC
        if nsec === 0 && sec <= TIMESTAMP32_MAX_SEC
          # timestamp32 = (sec: uint32be)
          [sec].pack('L>')
        else
          # timestamp64 (nsec: uint30be, sec: uint34be)
          nsec30 = nsec << 2
          sec_high2 = sec >> 32 # high 2 bits (`x & 0b11` is redandunt)
          sec_low32 = sec & 0xffffffff # low 32 bits
          [nsec30 | sec_high2, sec_low32].pack('L>2')
        end
      else
        # timestamp96 (nsec: uint32be, sec: int64be)
        [nsec, sec].pack('L>q>')
      end
    end

    def to_msgpack_ext
      self.class.to_msgpack_ext(sec, nsec)
    end

    def ==(other)
      other.class == self.class && sec == other.sec && nsec == other.nsec
    end
  end
end
