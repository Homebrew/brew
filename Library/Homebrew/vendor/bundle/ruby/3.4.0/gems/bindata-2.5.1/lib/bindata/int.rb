require 'thread'
require 'bindata/base_primitive'

module BinData
  # Defines a number of classes that contain an integer.  The integer
  # is defined by endian, signedness and number of bytes.

  module Int # :nodoc: all
    @@mutex = Mutex.new

    class << self
      def define_class(name, nbits, endian, signed)
        @@mutex.synchronize do
          unless BinData.const_defined?(name)
            new_class = Class.new(BinData::BasePrimitive)
            Int.define_methods(new_class, nbits, endian.to_sym, signed.to_sym)
            RegisteredClasses.register(name, new_class)

            BinData.const_set(name, new_class)
          end
        end

        BinData.const_get(name)
      end

      def define_methods(int_class, nbits, endian, signed)
        raise "nbits must be divisible by 8" unless (nbits % 8).zero?

        int_class.module_eval <<-END
          def assign(val)
            #{create_clamp_code(nbits, signed)}
            super(val)
          end

          def do_num_bytes
            #{nbits / 8}
          end

          #---------------
          private

          def sensible_default
            0
          end

          def value_to_binary_string(val)
            #{create_clamp_code(nbits, signed)}
            #{create_to_binary_s_code(nbits, endian, signed)}
          end

          def read_and_return_value(io)
            #{create_read_code(nbits, endian, signed)}
          end
        END
      end

      #-------------
      private

      def create_clamp_code(nbits, signed)
        if signed == :signed
          max = "(1 << (#{nbits} - 1)) - 1"
          min = "-((#{max}) + 1)"
        else
          max = "(1 << #{nbits}) - 1"
          min = "0"
        end

        "val = val.clamp(#{min}, #{max})"
      end

      def create_read_code(nbits, endian, signed)
        read_str = create_raw_read_code(nbits, endian, signed)

        if need_signed_conversion_code?(nbits, signed)
          "val = #{read_str} ; #{create_uint2int_code(nbits)}"
        else
          read_str
        end
      end

      def create_raw_read_code(nbits, endian, signed)
        # special case 8bit integers for speed
        if nbits == 8
          "io.readbytes(1).ord"
        else
          unpack_str   = create_read_unpack_code(nbits, endian, signed)
          assemble_str = create_read_assemble_code(nbits, endian)

          "(#{unpack_str} ; #{assemble_str})"
        end
      end

      def create_read_unpack_code(nbits, endian, signed)
        nbytes         = nbits / 8
        pack_directive = pack_directive(nbits, endian, signed)

        "ints = io.readbytes(#{nbytes}).unpack('#{pack_directive}')"
      end

      def create_read_assemble_code(nbits, endian)
        nwords = nbits / bits_per_word(nbits)

        idx = (0...nwords).to_a
        idx.reverse! if endian == :big

        parts = (0...nwords).collect do |i|
                  "(ints.at(#{idx[i]}) << #{bits_per_word(nbits) * i})"
                end
        parts[0] = parts[0].sub(/ << 0\b/, "")  # Remove " << 0" for optimisation

        parts.join(" + ")
      end

      def create_to_binary_s_code(nbits, endian, signed)
        # special case 8bit integers for speed
        return "(val & 0xff).chr" if nbits == 8

        pack_directive = pack_directive(nbits, endian, signed)
        words          = val_as_packed_words(nbits, endian)
        pack_str       = "[#{words}].pack('#{pack_directive}')"

        if need_signed_conversion_code?(nbits, signed)
          "#{create_int2uint_code(nbits)} ; #{pack_str}"
        else
          pack_str
        end
      end

      def val_as_packed_words(nbits, endian)
        nwords = nbits / bits_per_word(nbits)
        mask   = (1 << bits_per_word(nbits)) - 1

        vals = (0...nwords).collect { |i| "val >> #{bits_per_word(nbits) * i}" }
        vals[0] = vals[0].sub(/ >> 0\b/, "")  # Remove " >> 0" for optimisation
        vals.reverse! if (endian == :big)

        vals = vals.collect { |val| "#{val} & #{mask}" }  # TODO: "& mask" is needed to work around jruby bug. Remove this line when fixed.
        vals.join(',')
      end

      def create_int2uint_code(nbits)
        "val &= #{(1 << nbits) - 1}"
      end

      def create_uint2int_code(nbits)
        "(val >= #{1 << (nbits - 1)}) ? val - #{1 << nbits} : val"
      end

      def bits_per_word(nbits)
        (nbits % 64).zero? ? 64 :
        (nbits % 32).zero? ? 32 :
        (nbits % 16).zero? ? 16 :
                              8
      end

      def pack_directive(nbits, endian, signed)
        nwords = nbits / bits_per_word(nbits)

        directives = { 8 => 'C', 16 => 'S', 32 => 'L', 64 => 'Q' }

        d = directives[bits_per_word(nbits)]
        d += ((endian == :big) ? '>' : '<') unless d == 'C'

        if signed == :signed && directives.key?(nbits)
          (d * nwords).downcase
        else
          d * nwords
        end
      end

      def need_signed_conversion_code?(nbits, signed)
        signed == :signed && ![64, 32, 16].include?(nbits)
      end
    end
  end


  # Unsigned 1 byte integer.
  class Uint8 < BinData::BasePrimitive
    Int.define_methods(self, 8, :little, :unsigned)
  end

  # Signed 1 byte integer.
  class Int8 < BinData::BasePrimitive
    Int.define_methods(self, 8, :little, :signed)
  end

  # Create classes on demand
  module IntFactory
    def const_missing(name)
      mappings = {
        /^Uint(\d+)be$/ => [:big,    :unsigned],
        /^Uint(\d+)le$/ => [:little, :unsigned],
        /^Int(\d+)be$/  => [:big,    :signed],
        /^Int(\d+)le$/  => [:little, :signed]
      }

      mappings.each_pair do |regex, args|
        if regex =~ name.to_s
          nbits = $1.to_i
          if nbits > 0 && (nbits % 8).zero?
            return Int.define_class(name, nbits, *args)
          end
        end
      end

      super
    end
  end
  BinData.extend IntFactory
end
