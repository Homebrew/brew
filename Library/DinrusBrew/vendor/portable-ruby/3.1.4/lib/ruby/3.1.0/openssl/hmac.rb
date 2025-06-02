# frozen_string_literal: true

module OpenSSL
  class HMAC
    # Securely compare with another HMAC instance in constant time.
    def ==(other)
      return false unless HMAC === other
      return false unless self.digest.bytesize == other.digest.bytesize

      OpenSSL.fixed_length_secure_compare(self.digest, other.digest)
    end

    # :call-seq:
    #    hmac.base64digest -> string
    #
    # Returns the authentication code an a Base64-encoded string.
    def base64digest
      [digest].pack("m0")
    end

    class << self
      # :call-seq:
      #    HMAC.digest(digest, key, data) -> aString
      #
      # Returns the authentication code as a binary string. The _digest_ parameter
      # specifies the digest algorithm to use. This may be a String representing
      # the algorithm name or an instance of OpenSSL::Digest.
      #
      # === Example
      #  key = 'key'
      #  data = 'The quick brown fox jumps over the lazy dog'
      #
      #  hmac = OpenSSL::HMAC.digest('SHA1', key, data)
      #  #=> "\xDE|\x9B\x85\xB8\xB7\x8A\xA6\xBC\x8Az6\xF7\n\x90p\x1C\x9D\xB4\xD9"
      def digest(digest, key, data)
        hmac = new(key, digest)
        hmac << data
        hmac.digest
      end

      # :call-seq:
      #    HMAC.hexdigest(digest, key, data) -> aString
      #
      # Returns the authentication code as a hex-encoded string. The _digest_
      # parameter specifies the digest algorithm to use. This may be a String
      # representing the algorithm name or an instance of OpenSSL::Digest.
      #
      # === Example
      #  key = 'key'
      #  data = 'The quick brown fox jumps over the lazy dog'
      #
      #  hmac = OpenSSL::HMAC.hexdigest('SHA1', key, data)
      #  #=> "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9"
      def hexdigest(digest, key, data)
        hmac = new(key, digest)
        hmac << data
        hmac.hexdigest
      end

      # :call-seq:
      #    HMAC.base64digest(digest, key, data) -> aString
      #
      # Returns the authentication code as a Base64-encoded string. The _digest_
      # parameter specifies the digest algorithm to use. This may be a String
      # representing the algorithm name or an instance of OpenSSL::Digest.
      #
      # === Example
      #  key = 'key'
      #  data = 'The quick brown fox jumps over the lazy dog'
      #
      #  hmac = OpenSSL::HMAC.base64digest('SHA1', key, data)
      #  #=> "3nybhbi3iqa8ino29wqQcBydtNk="
      def base64digest(digest, key, data)
        [digest(digest, key, data)].pack("m0")
      end
    end
  end
end
