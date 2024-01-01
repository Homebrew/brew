require 'thread'
require 'bindata/base_primitive'

module BinData
  # Defines a number of classes that contain a bit based integer.
  # The integer is defined by endian and number of bits.

  module BitField #:nodoc: all
    @@mutex = Mutex.new

    class << self
      def define_class(name, nbits, endian, signed = :unsigned)
        @@mutex.synchronize do
          unless BinData.const_defined?(name)
            new_class = Class.new(BinData::BasePrimitive)
            BitField.define_methods(new_class, nbits, endian.to_sym, signed.to_sym)
            RegisteredClasses.register(name, new_class)

            BinData.const_set(name, new_class)
          end
        end

        BinData.const_get(name)
      end

      def define_methods(bit_class, nbits, endian, signed)
        bit_class.module_eval <<-END
          #{create_params_code(nbits)}

          def assign(val)
            #{create_nbits_code(nbits)}
            #{create_clamp_code(nbits, signed)}
            super(val)
          end

          def do_write(io)
            #{create_nbits_code(nbits)}
            val = _value
            #{create_int2uint_code(nbits, signed)}
            io.writebits(val, #{nbits}, :#{endian})
          end

          def do_num_bytes
            #{create_nbits_code(nbits)}
            #{create_do_num_bytes_code(nbits)}
          end

          def bit_aligned?
            true
          end

          #---------------
          private

          def read_and_return_value(io)
            #{create_nbits_code(nbits)}
            val = io.readbits(#{nbits}, :#{endian})
            #{create_uint2int_code(nbits, signed)}
            val
          end

          def sensible_default
            0
          end
        END
      end

      def create_params_code(nbits)
        if nbits == :nbits
          "mandatory_parameter :nbits"
        else
          ""
        end
      end

      def create_nbits_code(nbits)
        if nbits == :nbits
          "nbits = eval_parameter(:nbits)"
        else
          ""
        end
      end

      def create_do_num_bytes_code(nbits)
        if nbits == :nbits
          "nbits / 8.0"
        else
          nbits / 8.0
        end
      end

      def create_clamp_code(nbits, signed)
        if nbits == :nbits
          create_dynamic_clamp_code(signed)
        else
          create_fixed_clamp_code(nbits, signed)
        end
      end

      def create_dynamic_clamp_code(signed)
        if signed == :signed
          max = "(1 << (nbits - 1)) - 1"
          min = "-((#{max}) + 1)"
        else
          max = "(1 << nbits) - 1"
          min = "0"
        end

        "val = val.clamp(#{min}, #{max})"
      end

      def create_fixed_clamp_code(nbits, signed)
        if nbits == 1 && signed == :signed
          raise "signed bitfield must have more than one bit"
        end

        if signed == :signed
          max = "(1 << (#{nbits} - 1)) - 1"
          min = "-((#{max}) + 1)"
        else
          min = "0"
          max = "(1 << #{nbits}) - 1"
        end

        clamp = "(val = val.clamp(#{min}, #{max}))"

        if nbits == 1
          # allow single bits to be used as booleans
          clamp = "(val == true) ? 1 : (not val) ? 0 : #{clamp}"
        end

        "val = #{clamp}"
      end

      def create_int2uint_code(nbits, signed)
        if signed != :signed
          ""
        elsif nbits == :nbits
          "val &= (1 << nbits) - 1"
        else
          "val &= #{(1 << nbits) - 1}"
        end
      end

      def create_uint2int_code(nbits, signed)
        if signed != :signed
          ""
        elsif nbits == :nbits
          "val -= (1 << nbits) if (val >= (1 << (nbits - 1)))"
        else
          "val -= #{1 << nbits} if (val >= #{1 << (nbits - 1)})"
        end
      end
    end
  end

  # Create classes for dynamic bitfields
  {
    "Bit"    => :big,
    "BitLe"  => :little,
    "Sbit"   => [:big, :signed],
    "SbitLe" => [:little, :signed],
  }.each_pair { |name, args| BitField.define_class(name, :nbits, *args) }

  # Create classes on demand
  module BitFieldFactory
    def const_missing(name)
      mappings = {
        /^Bit(\d+)$/    => :big,
        /^Bit(\d+)le$/  => :little,
        /^Sbit(\d+)$/   => [:big, :signed],
        /^Sbit(\d+)le$/ => [:little, :signed]
      }

      mappings.each_pair do |regex, args|
        if regex =~ name.to_s
          nbits = $1.to_i
          return BitField.define_class(name, nbits, *args)
        end
      end

      super(name)
    end
  end
  BinData.extend BitFieldFactory
end
