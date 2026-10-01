# frozen_string_literal: true

module ELFTools
  # Define some util methods.
  module Util
    # How many bytes {ClassMethods#cstring} takes from a stream at a time. Long
    # enough that a name is usually read in one, short enough that reading one
    # never reaches far past its end.
    CSTRING_CHUNK = 64

    # Class methods.
    module ClassMethods
      # Round up the number to be multiple of
      # +2**bit+.
      # @param [Integer] num Number to be rounded-up.
      # @param [Integer] bit How many bit to be aligned.
      # @return [Integer] See examples.
      # @example
      #   align(10, 1) #=> 10
      #   align(10, 2) #=> 12
      #   align(10, 3) #=> 16
      #   align(10, 4) #=> 16
      #   align(10, 5) #=> 32
      def align(num, bit)
        n = 2**bit
        return num if (num % n).zero?

        (num + n) & ~(n - 1)
      end

      # Checks a value is one the bits recording it can hold.
      #
      # Several of the values a file records share a byte with others, so a
      # value too large for its bits would be written over its neighbours
      # instead of being rejected.
      # @param [Integer] value The value.
      # @param [Integer] bits How many bits record it.
      # @param [String] name What the value is, for the error to name.
      # @return [Integer] The value.
      # @raise [ArgumentError] If the bits cannot hold it.
      # @example
      #   Util.fits!(16, 4, 'Symbol binding')
      #   #=> ArgumentError: Symbol binding must be in 0..15, got 16
      def fits!(value, bits, name)
        highest = (1 << bits) - 1
        return value if value.is_a?(Integer) && value.between?(0, highest)

        raise ArgumentError, format('%s must be in 0..%d, got %p', name, highest, value)
      end

      # Fetch the correct value from module +mod+.
      #
      # See {ELFTools::ELFFile#segment_by_type} for how to
      # use this method.
      # @param [Module] mod The module defined constant numbers.
      # @param [Integer, Symbol, String] val
      #   Desired value.
      # @return [Integer]
      #   Currently this method always return a value
      #   from {ELFTools::Constants}.
      def to_constant(mod, val)
        # Ignore the outest name.
        module_name = mod.name.sub('ELFTools::', '')
        # if val is an integer, check if exists in mod
        if val.is_a?(Integer)
          return val if values_of(mod).key?(val)

          raise ArgumentError, "No constants in #{module_name} is #{val}"
        end
        val = val.to_s.upcase
        prefix = module_name.split('::')[-1]
        val = "#{prefix}_#{val}" unless val.start_with?(prefix)
        value = constants_of(mod)[val]
        raise ArgumentError, "No constants in #{module_name} named \"#{val}\"" if value.nil?

        value
      end

      # Read from stream until reach a null-byte.
      #
      # The stream is left just past the null-byte.
      # @param [#pos=, #read] stream Streaming object.
      # @param [Integer] offset Start from here.
      # @return [String] Result string will never contain null byte.
      # @example
      #   Util.cstring(File.open('/bin/cat'), 0)
      #   #=> "\x7FELF\x02\x01\x01"
      def cstring(stream, offset)
        stream.pos = offset
        ret = +''
        loop do
          chunk = stream.read(CSTRING_CHUNK)
          return nil if chunk.nil? # reach EOF

          stop = chunk.index("\x00")
          if stop
            stream.pos = offset + ret.bytesize + stop + 1
            return ret << chunk.byteslice(0, stop)
          end

          ret << chunk
        end
      end

      # Select objects from enumerator with +.type+ property
      # equals to +type+.
      #
      # Different from naive +Array#select+ is this method
      # will yield block whenever find a desired object.
      #
      # This method is used to simplify the same logic in methods
      # {ELFFile#sections_by_type}, {ELFFile#segments_by_type}, etc.
      # @param [Enumerator] enum An enumerator for further select.
      # @param [Object] type The type you want.
      # @return [Array<Object>]
      #   The return value will be objects in +enum+ with attribute
      #   +.type+ equals to +type+.
      def select_by_type(enum, type)
        enum.select do |obj|
          if obj.type == type
            yield obj if block_given?
            true
          end
        end
      end

      private

      # What a module names each of its constants, and what each is worth.
      #
      # Names are compared upcased, which is how a constant keeping the case
      # the ABI wrote it in, +SHT_GNU_verneed+ for one, is found by the name it
      # is asked for. Read once per module, because reading them is more work
      # than the lookup it is for.
      # @param [Module] mod The module.
      # @return [Hash{String => Integer}] The constants, by their upcased name.
      def constants_of(mod)
        (@constants_of ||= {})[mod] ||= mod.constants.each_with_object({}) do |constant, table|
          # A constant still waiting to be autoloaded is left alone, so that
          # asking after one never loads what nothing has asked for.
          next if mod.autoload?(constant)

          table[constant.to_s.upcase] ||= mod.const_get(constant)
        end
      end

      # Which values a module names a constant for.
      # @param [Module] mod The module.
      # @return [Hash{Integer => Boolean}] The values, as the keys.
      def values_of(mod)
        (@values_of ||= {})[mod] ||= constants_of(mod).values.to_h { |value| [value, true] }
      end
    end
    extend ClassMethods
  end
end
