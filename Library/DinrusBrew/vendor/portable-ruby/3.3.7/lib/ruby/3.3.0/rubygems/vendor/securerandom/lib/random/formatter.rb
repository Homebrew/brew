# -*- coding: us-ascii -*-
# frozen_string_literal: true

# == \Random number formatter.
#
# Formats generated random numbers in many manners. When <tt>'random/formatter'</tt>
# is required, several methods are added to empty core module <tt>Gem::Random::Formatter</tt>,
# making them available as Random's instance and module methods.
#
# Standard library Gem::SecureRandom is also extended with the module, and the methods
# described below are available as a module methods in it.
#
# === Examples
#
# Generate random hexadecimal strings:
#
#   require 'rubygems/vendor/securerandom/lib/random/formatter'
#
#   prng = Random.new
#   prng.hex(10) #=> "52750b30ffbc7de3b362"
#   prng.hex(10) #=> "92b15d6c8dc4beb5f559"
#   prng.hex(13) #=> "39b290146bea6ce975c37cfc23"
#   # or just
#   Random.hex #=> "1aed0c631e41be7f77365415541052ee"
#
# Generate random base64 strings:
#
#   prng.base64(10) #=> "EcmTPZwWRAozdA=="
#   prng.base64(10) #=> "KO1nIU+p9DKxGg=="
#   prng.base64(12) #=> "7kJSM/MzBJI+75j8"
#   Random.base64(4) #=> "bsQ3fQ=="
#
# Generate random binary strings:
#
#   prng.random_bytes(10) #=> "\016\t{\370g\310pbr\301"
#   prng.random_bytes(10) #=> "\323U\030TO\234\357\020\a\337"
#   Random.random_bytes(6) #=> "\xA1\xE6Lr\xC43"
#
# Generate alphanumeric strings:
#
#   prng.alphanumeric(10) #=> "S8baxMJnPl"
#   prng.alphanumeric(10) #=> "aOxAg8BAJe"
#   Random.alphanumeric #=> "TmP9OsJHJLtaZYhP"
#
# Generate UUIDs:
#
#   prng.uuid #=> "2d931510-d99f-494a-8c67-87feb05e1594"
#   prng.uuid #=> "bad85eb9-0713-4da7-8d36-07a8e4b00eab"
#   Random.uuid #=> "f14e0271-de96-45cc-8911-8910292a42cd"
#
# All methods are available in the standard library Gem::SecureRandom, too:
#
#   Gem::SecureRandom.hex #=> "05b45376a30c67238eb93b16499e50cf"

module Gem::Random::Formatter

  # Generate a random binary string.
  #
  # The argument _n_ specifies the length of the result string.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in future.
  #
  # The result may contain any byte: "\x00" - "\xff".
  #
  #   require 'rubygems/vendor/securerandom/lib/random/formatter'
  #
  #   Random.random_bytes #=> "\xD8\\\xE0\xF4\r\xB2\xFC*WM\xFF\x83\x18\xF45\xB6"
  #   # or
  #   prng = Random.new
  #   prng.random_bytes #=> "m\xDC\xFC/\a\x00Uf\xB2\xB2P\xBD\xFF6S\x97"
  def random_bytes(n=nil)
    n = n ? n.to_int : 16
    gen_random(n)
  end

  # Generate a random hexadecimal string.
  #
  # The argument _n_ specifies the length, in bytes, of the random number to be generated.
  # The length of the resulting hexadecimal string is twice of _n_.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The result may contain 0-9 and a-f.
  #
  #   require 'rubygems/vendor/securerandom/lib/random/formatter'
  #
  #   Random.hex #=> "eb693ec8252cd630102fd0d0fb7c3485"
  #   # or
  #   prng = Random.new
  #   prng.hex #=> "91dc3bfb4de5b11d029d376634589b61"
  def hex(n=nil)
    random_bytes(n).unpack1("H*")
  end

  # Generate a random base64 string.
  #
  # The argument _n_ specifies the length, in bytes, of the random number
  # to be generated. The length of the result string is about 4/3 of _n_.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The result may contain A-Z, a-z, 0-9, "+", "/" and "=".
  #
  #   require 'rubygems/vendor/securerandom/lib/random/formatter'
  #
  #   Random.base64 #=> "/2BuBuLf3+WfSKyQbRcc/A=="
  #   # or
  #   prng = Random.new
  #   prng.base64 #=> "6BbW0pxO0YENxn38HMUbcQ=="
  #
  # See RFC 3548 for the definition of base64.
  def base64(n=nil)
    [random_bytes(n)].pack("m0")
  end

  # Generate a random URL-safe base64 string.
  #
  # The argument _n_ specifies the length, in bytes, of the random number
  # to be generated. The length of the result string is about 4/3 of _n_.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The boolean argument _padding_ specifies the padding.
  # If it is false or nil, padding is not generated.
  # Otherwise padding is generated.
  # By default, padding is not generated because "=" may be used as a URL delimiter.
  #
  # The result may contain A-Z, a-z, 0-9, "-" and "_".
  # "=" is also used if _padding_ is true.
  #
  #   require 'rubygems/vendor/securerandom/lib/random/formatter'
  #
  #   Random.urlsafe_base64 #=> "b4GOKm4pOYU_-BOXcrUGDg"
  #   # or
  #   prng = Random.new
  #   prng.urlsafe_base64 #=> "UZLdOkzop70Ddx-IJR0ABg"
  #
  #   prng.urlsafe_base64(nil, true) #=> "i0XQ-7gglIsHGV2_BNPrdQ=="
  #   prng.urlsafe_base64(nil, true) #=> "-M8rLhr7JEpJlqFGUMmOxg=="
  #
  # See RFC 3548 for the definition of URL-safe base64.
  def urlsafe_base64(n=nil, padding=false)
    s = [random_bytes(n)].pack("m0")
    s.tr!("+/", "-_")
    s.delete!("=") unless padding
    s
  end

  # Generate a random v4 UUID (Universally Unique IDentifier).
  #
  #   require 'rubygems/vendor/securerandom/lib/random/formatter'
  #
  #   Random.uuid #=> "2d931510-d99f-494a-8c67-87feb05e1594"
  #   Random.uuid #=> "bad85eb9-0713-4da7-8d36-07a8e4b00eab"
  #   # or
  #   prng = Random.new
  #   prng.uuid #=> "62936e70-1815-439b-bf89-8492855a7e6b"
  #
  # The version 4 UUID is purely random (except the version).
  # It doesn't contain meaningful information such as MAC addresses, timestamps, etc.
  #
  # The result contains 122 random bits (15.25 random bytes).
  #
  # See RFC4122[https://datatracker.ietf.org/doc/html/rfc4122] for details of UUID.
  #
  def uuid
    ary = random_bytes(16).unpack("NnnnnN")
    ary[2] = (ary[2] & 0x0fff) | 0x4000
    ary[3] = (ary[3] & 0x3fff) | 0x8000
    "%08x-%04x-%04x-%04x-%04x%08x" % ary
  end

  alias uuid_v4 uuid

  # Generate a random v7 UUID (Universally Unique IDentifier).
  #
  #   require 'rubygems/vendor/securerandom/lib/random/formatter'
  #
  #   Random.uuid_v7 # => "0188d4c3-1311-7f96-85c7-242a7aa58f1e"
  #   Random.uuid_v7 # => "0188d4c3-16fe-744f-86af-38fa04c62bb5"
  #   Random.uuid_v7 # => "0188d4c3-1af8-764f-b049-c204ce0afa23"
  #   Random.uuid_v7 # => "0188d4c3-1e74-7085-b14f-ef6415dc6f31"
  #   #                    |<--sorted-->| |<----- random ---->|
  #
  #   # or
  #   prng = Random.new
  #   prng.uuid_v7 # => "0188ca51-5e72-7950-a11d-def7ff977c98"
  #
  # The version 7 UUID starts with the least significant 48 bits of a 64 bit
  # Unix timestamp (milliseconds since the epoch) and fills the remaining bits
  # with random data, excluding the version and variant bits.
  #
  # This allows version 7 UUIDs to be sorted by creation time.  Time ordered
  # UUIDs can be used for better database index locality of newly inserted
  # records, which may have a significant performance benefit compared to random
  # data inserts.
  #
  # The result contains 74 random bits (9.25 random bytes).
  #
  # Note that this method cannot be made reproducable because its output
  # includes not only random bits but also timestamp.
  #
  # See draft-ietf-uuidrev-rfc4122bis[https://datatracker.ietf.org/doc/draft-ietf-uuidrev-rfc4122bis/]
  # for details of UUIDv7.
  #
  # ==== Monotonicity
  #
  # UUIDv7 has millisecond precision by default, so multiple UUIDs created
  # within the same millisecond are not issued in monotonically increasing
  # order.  To create UUIDs that are time-ordered with sub-millisecond
  # precision, up to 12 bits of additional timestamp may added with
  # +extra_timestamp_bits+.  The extra timestamp precision comes at the expense
  # of random bits.  Setting <tt>extra_timestamp_bits: 12</tt> provides ~244ns
  # of precision, but only 62 random bits (7.75 random bytes).
  #
  #   prng = Random.new
  #   Array.new(4) { prng.uuid_v7(extra_timestamp_bits: 12) }
  #   # =>
  #   ["0188d4c7-13da-74f9-8b53-22a786ffdd5a",
  #    "0188d4c7-13da-753b-83a5-7fb9b2afaeea",
  #    "0188d4c7-13da-754a-88ea-ac0baeedd8db",
  #    "0188d4c7-13da-7557-83e1-7cad9cda0d8d"]
  #   # |<--- sorted --->| |<-- random --->|
  #
  #   Array.new(4) { prng.uuid_v7(extra_timestamp_bits: 8) }
  #   # =>
  #   ["0188d4c7-3333-7a95-850a-de6edb858f7e",
  #    "0188d4c7-3333-7ae8-842e-bc3a8b7d0cf9",  # <- out of order
  #    "0188d4c7-3333-7ae2-995a-9f135dc44ead",  # <- out of order
  #    "0188d4c7-3333-7af9-87c3-8f612edac82e"]
  #   # |<--- sorted -->||<---- random --->|
  #
  # Any rollbacks of the system clock will break monotonicity.  UUIDv7 is based
  # on UTC, which excludes leap seconds and can rollback the clock.  To avoid
  # this, the system clock can synchronize with an NTP server configured to use
  # a "leap smear" approach.  NTP or PTP will also be needed to synchronize
  # across distributed nodes.
  #
  # Counters and other mechanisms for stronger guarantees of monotonicity are
  # not implemented.  Applications with stricter requirements should follow
  # {Section 6.2}[https://www.ietf.org/archive/id/draft-ietf-uuidrev-rfc4122bis-07.html#monotonicity_counters]
  # of the specification.
  #
  def uuid_v7(extra_timestamp_bits: 0)
    case (extra_timestamp_bits = Integer(extra_timestamp_bits))
    when 0 # min timestamp precision
      ms = Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
      rand = random_bytes(10)
      rand.setbyte(0, rand.getbyte(0) & 0x0f | 0x70) # version
      rand.setbyte(2, rand.getbyte(2) & 0x3f | 0x80) # variant
      "%08x-%04x-%s" % [
        (ms & 0x0000_ffff_ffff_0000) >> 16,
        (ms & 0x0000_0000_0000_ffff),
        rand.unpack("H4H4H12").join("-")
      ]

    when 12 # max timestamp precision
      ms, ns = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
        .divmod(1_000_000)
      extra_bits = ns * 4096 / 1_000_000
      rand = random_bytes(8)
      rand.setbyte(0, rand.getbyte(0) & 0x3f | 0x80) # variant
      "%08x-%04x-7%03x-%s" % [
        (ms & 0x0000_ffff_ffff_0000) >> 16,
        (ms & 0x0000_0000_0000_ffff),
        extra_bits,
        rand.unpack("H4H12").join("-")
      ]

    when (0..12) # the generic version is slower than the special cases above
      rand_a, rand_b1, rand_b2, rand_b3 = random_bytes(10).unpack("nnnN")
      rand_mask_bits = 12 - extra_timestamp_bits
      ms, ns = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
        .divmod(1_000_000)
      "%08x-%04x-%04x-%04x-%04x%08x" % [
        (ms & 0x0000_ffff_ffff_0000) >> 16,
        (ms & 0x0000_0000_0000_ffff),
        0x7000 |
          ((ns * (1 << extra_timestamp_bits) / 1_000_000) << rand_mask_bits) |
          rand_a & ((1 << rand_mask_bits) - 1),
        0x8000 | (rand_b1 & 0x3fff),
        rand_b2,
        rand_b3
      ]

    else
      raise ArgumentError, "extra_timestamp_bits must be in 0..12"
    end
  end

  # Internal interface to Random; Generate random data _n_ bytes.
  private def gen_random(n)
    self.bytes(n)
  end

  # Generate a string that randomly draws from a
  # source array of characters.
  #
  # The argument _source_ specifies the array of characters from which
  # to generate the string.
  # The argument _n_ specifies the length, in characters, of the string to be
  # generated.
  #
  # The result may contain whatever characters are in the source array.
  #
  #   require 'rubygems/vendor/securerandom/lib/random/formatter'
  #
  #   prng.choose([*'l'..'r'], 16) #=> "lmrqpoonmmlqlron"
  #   prng.choose([*'0'..'9'], 5)  #=> "27309"
  private def choose(source, n)
    size = source.size
    m = 1
    limit = size
    while limit * size <= 0x100000000
      limit *= size
      m += 1
    end
    result = ''.dup
    while m <= n
      rs = random_number(limit)
      is = rs.digits(size)
      (m-is.length).times { is << 0 }
      result << source.values_at(*is).join('')
      n -= m
    end
    if 0 < n
      rs = random_number(limit)
      is = rs.digits(size)
      if is.length < n
        (n-is.length).times { is << 0 }
      else
        is.pop while n < is.length
      end
      result.concat source.values_at(*is).join('')
    end
    result
  end

  # The default character list for #alphanumeric.
  ALPHANUMERIC = [*'A'..'Z', *'a'..'z', *'0'..'9']

  # Generate a random alphanumeric string.
  #
  # The argument _n_ specifies the length, in characters, of the alphanumeric
  # string to be generated.
  # The argument _chars_ specifies the character list which the result is
  # consist of.
  #
  # If _n_ is not specified or is nil, 16 is assumed.
  # It may be larger in the future.
  #
  # The result may contain A-Z, a-z and 0-9, unless _chars_ is specified.
  #
  #   require 'rubygems/vendor/securerandom/lib/random/formatter'
  #
  #   Random.alphanumeric     #=> "2BuBuLf3WfSKyQbR"
  #   # or
  #   prng = Random.new
  #   prng.alphanumeric(10) #=> "i6K93NdqiH"
  #
  #   Random.alphanumeric(4, chars: [*"0".."9"]) #=> "2952"
  #   # or
  #   prng = Random.new
  #   prng.alphanumeric(10, chars: [*"!".."/"]) #=> ",.,++%/''."
  def alphanumeric(n = nil, chars: ALPHANUMERIC)
    n = 16 if n.nil?
    choose(chars, n)
  end
end
