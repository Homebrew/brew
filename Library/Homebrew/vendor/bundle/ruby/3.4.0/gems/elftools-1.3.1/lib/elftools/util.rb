# frozen_string_literal: true

module ELFTools
  # Define some util methods.
  module Util
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
          return val if mod.constants.any? { |c| mod.const_get(c) == val }

          raise ArgumentError, "No constants in #{module_name} is #{val}"
        end
        val = val.to_s.upcase
        prefix = module_name.split('::')[-1]
        val = "#{prefix}_#{val}" unless val.start_with?(prefix)
        val = val.to_sym
        raise ArgumentError, "No constants in #{module_name} named \"#{val}\"" unless mod.const_defined?(val)

        mod.const_get(val)
      end

      # Read from stream until reach a null-byte.
      # @param [#pos=, #read] stream Streaming object
      # @param [Integer] offset Start from here.
      # @return [String] Result string will never contain null byte.
      # @example
      #   Util.cstring(File.open('/bin/cat'), 0)
      #   #=> "\x7FELF\x02\x01\x01"
      def cstring(stream, offset)
        stream.pos = offset
        # read until "\x00"
        ret = ''
        loop do
          c = stream.read(1)
          return nil if c.nil? # reach EOF
          break if c == "\x00"

          ret += c
        end
        ret
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
    end
    extend ClassMethods
  end
end
