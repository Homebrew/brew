# frozen_string_literal: true

module Prism
  # A parser for the pack template language.
  module Pack
    %i[
      SPACE
      COMMENT
      INTEGER
      UTF8
      BER
      FLOAT
      STRING_SPACE_PADDED
      STRING_NULL_PADDED
      STRING_NULL_TERMINATED
      STRING_MSB
      STRING_LSB
      STRING_HEX_HIGH
      STRING_HEX_LOW
      STRING_UU
      STRING_MIME
      STRING_BASE64
      STRING_FIXED
      STRING_POINTER
      MOVE
      BACK
      NULL

      UNSIGNED
      SIGNED
      SIGNED_NA

      AGNOSTIC_ENDIAN
      LITTLE_ENDIAN
      BIG_ENDIAN
      NATIVE_ENDIAN
      ENDIAN_NA

      SIZE_SHORT
      SIZE_INT
      SIZE_LONG
      SIZE_LONG_LONG
      SIZE_8
      SIZE_16
      SIZE_32
      SIZE_64
      SIZE_P
      SIZE_NA

      LENGTH_FIXED
      LENGTH_MAX
      LENGTH_RELATIVE
      LENGTH_NA
    ].each do |const|
      const_set(const, const)
    end

    # A directive in the pack template language.
    class Directive
      # A symbol representing the version of Ruby.
      attr_reader :version

      # A symbol representing whether or not we are packing or unpacking.
      attr_reader :variant

      # A byteslice of the source string that this directive represents.
      attr_reader :source

      # The type of the directive.
      attr_reader :type

      # The type of signedness of the directive.
      attr_reader :signed

      # The type of endianness of the directive.
      attr_reader :endian

      # The size of the directive.
      attr_reader :size

      # The length type of this directive (used for integers).
      attr_reader :length_type

      # The length of this directive (used for integers).
      attr_reader :length

      # Initialize a new directive with the given values.
      def initialize(version, variant, source, type, signed, endian, size, length_type, length)
        @version = version
        @variant = variant
        @source = source
        @type = type
        @signed = signed
        @endian = endian
        @size = size
        @length_type = length_type
        @length = length
      end

      # The descriptions of the various types of endianness.
      ENDIAN_DESCRIPTIONS = {
        AGNOSTIC_ENDIAN: "agnostic",
        LITTLE_ENDIAN: "little-endian (VAX)",
        BIG_ENDIAN: "big-endian (network)",
        NATIVE_ENDIAN: "native-endian",
        ENDIAN_NA: "n/a"
      }

      # The descriptions of the various types of signedness.
      SIGNED_DESCRIPTIONS = {
        UNSIGNED: "unsigned",
        SIGNED: "signed",
        SIGNED_NA: "n/a"
      }

      # The descriptions of the various types of sizes.
      SIZE_DESCRIPTIONS = {
        SIZE_SHORT: "short",
        SIZE_INT: "int-width",
        SIZE_LONG: "long",
        SIZE_LONG_LONG: "long long",
        SIZE_8: "8-bit",
        SIZE_16: "16-bit",
        SIZE_32: "32-bit",
        SIZE_64: "64-bit",
        SIZE_P: "pointer-width"
      }

      # Provide a human-readable description of the directive.
      def describe
        case type
        when SPACE
          "whitespace"
        when COMMENT
          "comment"
        when INTEGER
          if size == SIZE_8
            base = "#{SIGNED_DESCRIPTIONS[signed]} #{SIZE_DESCRIPTIONS[size]} integer"
          else
            base = "#{SIGNED_DESCRIPTIONS[signed]} #{SIZE_DESCRIPTIONS[size]} #{ENDIAN_DESCRIPTIONS[endian]} integer"
          end
          case length_type
          when LENGTH_FIXED
            if length > 1
              base + ", x#{length}"
            else
              base
            end
          when LENGTH_MAX
            base + ", as many as possible"
          end
        when UTF8
          "UTF-8 character"
        when BER
          "BER-compressed integer"
        when FLOAT
          "#{SIZE_DESCRIPTIONS[size]} #{ENDIAN_DESCRIPTIONS[endian]} float"
        when STRING_SPACE_PADDED
          "arbitrary binary string (space padded)"
        when STRING_NULL_PADDED
          "arbitrary binary string (null padded, count is width)"
        when STRING_NULL_TERMINATED
          "arbitrary binary string (null padded, count is width), except that null is added with *"
        when STRING_MSB
          "bit string (MSB first)"
        when STRING_LSB
          "bit string (LSB first)"
        when STRING_HEX_HIGH
          "hex string (high nibble first)"
        when STRING_HEX_LOW
          "hex string (low nibble first)"
        when STRING_UU
          "UU-encoded string"
        when STRING_MIME
          "quoted printable, MIME encoding"
        when STRING_BASE64
          "base64 encoded string"
        when STRING_FIXED
          "pointer to a structure (fixed-length string)"
        when STRING_POINTER
          "pointer to a null-terminated string"
        when MOVE
          "move to absolute position"
        when BACK
          "back up a byte"
        when NULL
          "null byte"
        else
          raise
        end
      end
    end

    # The result of parsing a pack template.
    class Format
      # A list of the directives in the template.
      attr_reader :directives

      # The encoding of the template.
      attr_reader :encoding

      # Create a new Format with the given directives and encoding.
      def initialize(directives, encoding)
        @directives = directives
        @encoding = encoding
      end

      # Provide a human-readable description of the format.
      def describe
        source_width = directives.map { |d| d.source.inspect.length }.max
        directive_lines = directives.map do |directive|
          if directive.type == SPACE
            source = directive.source.inspect
          else
            source = directive.source
          end
          "  #{source.ljust(source_width)}  #{directive.describe}"
        end

        (["Directives:"] + directive_lines + ["Encoding:", "  #{encoding}"]).join("\n")
      end
    end
  end
end
