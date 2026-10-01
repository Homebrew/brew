require 'bindata/base_primitive'

module BinData
  # Defines a number of classes that contain a floating point number.
  # The float is defined by precision and endian.

  module FloatingPoint # :nodoc: all
    class << self
      PRECISION = {
        single: 4,
        double: 8,
      }

      PACK_CODE = {
        [:single, :little] => 'e',
        [:single, :big]    => 'g',
        [:double, :little] => 'E',
        [:double, :big]    => 'G'
      }

      def define_methods(float_class, precision, endian)
        float_class.module_eval <<-END
          def do_num_bytes
            #{create_num_bytes_code(precision)}
          end

          #---------------
          private

          def sensible_default
            0.0
          end

          def value_to_binary_string(val)
            #{create_to_binary_s_code(precision, endian)}
          end

          def read_and_return_value(io)
            #{create_read_code(precision, endian)}
          end
        END
      end

      def create_num_bytes_code(precision)
        PRECISION[precision]
      end

      def create_read_code(precision, endian)
        nbytes = PRECISION[precision]
        unpack = PACK_CODE[[precision, endian]]

        "io.readbytes(#{nbytes}).unpack1('#{unpack}')"
      end

      def create_to_binary_s_code(precision, endian)
        pack = PACK_CODE[[precision, endian]]

        "[val].pack('#{pack}')"
      end
    end
  end


  # Single precision floating point number in little endian format
  class FloatLe < BinData::BasePrimitive
    FloatingPoint.define_methods(self, :single, :little)
  end

  # Single precision floating point number in big endian format
  class FloatBe < BinData::BasePrimitive
    FloatingPoint.define_methods(self, :single, :big)
  end

  # Double precision floating point number in little endian format
  class DoubleLe < BinData::BasePrimitive
    FloatingPoint.define_methods(self, :double, :little)
  end

  # Double precision floating point number in big endian format
  class DoubleBe < BinData::BasePrimitive
    FloatingPoint.define_methods(self, :double, :big)
  end
end
