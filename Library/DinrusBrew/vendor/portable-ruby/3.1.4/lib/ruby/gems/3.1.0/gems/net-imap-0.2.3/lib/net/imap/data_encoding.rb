# frozen_string_literal: true

require_relative "errors"

module Net
  class IMAP < Protocol

    # Decode a string from modified UTF-7 format to UTF-8.
    #
    # UTF-7 is a 7-bit encoding of Unicode [UTF7].  IMAP uses a
    # slightly modified version of this to encode mailbox names
    # containing non-ASCII characters; see [IMAP] section 5.1.3.
    #
    # Net::IMAP does _not_ automatically encode and decode
    # mailbox names to and from UTF-7.
    def self.decode_utf7(s)
      return s.gsub(/&([^-]+)?-/n) {
        if $1
          ($1.tr(",", "/") + "===").unpack1("m").encode(Encoding::UTF_8, Encoding::UTF_16BE)
        else
          "&"
        end
      }
    end

    # Encode a string from UTF-8 format to modified UTF-7.
    def self.encode_utf7(s)
      return s.gsub(/(&)|[^\x20-\x7e]+/) {
        if $1
          "&-"
        else
          base64 = [$&.encode(Encoding::UTF_16BE)].pack("m0")
          "&" + base64.delete("=").tr("/", ",") + "-"
        end
      }.force_encoding("ASCII-8BIT")
    end

    # Formats +time+ as an IMAP-style date.
    def self.format_date(time)
      return time.strftime('%d-%b-%Y')
    end

    # Formats +time+ as an IMAP-style date-time.
    def self.format_datetime(time)
      return time.strftime('%d-%b-%Y %H:%M %z')
    end

    # Common validators of number and nz_number types
    module NumValidator # :nodoc
      module_function

      # Check is passed argument valid 'number' in RFC 3501 terminology
      def valid_number?(num)
        # [RFC 3501]
        # number          = 1*DIGIT
        #                    ; Unsigned 32-bit integer
        #                    ; (0 <= n < 4,294,967,296)
        num >= 0 && num < 4294967296
      end

      # Check is passed argument valid 'nz_number' in RFC 3501 terminology
      def valid_nz_number?(num)
        # [RFC 3501]
        # nz-number       = digit-nz *DIGIT
        #                    ; Non-zero unsigned 32-bit integer
        #                    ; (0 < n < 4,294,967,296)
        num != 0 && valid_number?(num)
      end

      # Check is passed argument valid 'mod_sequence_value' in RFC 4551 terminology
      def valid_mod_sequence_value?(num)
        # mod-sequence-value  = 1*DIGIT
        #                        ; Positive unsigned 64-bit integer
        #                        ; (mod-sequence)
        #                        ; (1 <= n < 18,446,744,073,709,551,615)
        num >= 1 && num < 18446744073709551615
      end

      # Ensure argument is 'number' or raise DataFormatError
      def ensure_number(num)
        return if valid_number?(num)

        msg = "number must be unsigned 32-bit integer: #{num}"
        raise DataFormatError, msg
      end

      # Ensure argument is 'nz_number' or raise DataFormatError
      def ensure_nz_number(num)
        return if valid_nz_number?(num)

        msg = "nz_number must be non-zero unsigned 32-bit integer: #{num}"
        raise DataFormatError, msg
      end

      # Ensure argument is 'mod_sequence_value' or raise DataFormatError
      def ensure_mod_sequence_value(num)
        return if valid_mod_sequence_value?(num)

        msg = "mod_sequence_value must be unsigned 64-bit integer: #{num}"
        raise DataFormatError, msg
      end

    end

  end
end
