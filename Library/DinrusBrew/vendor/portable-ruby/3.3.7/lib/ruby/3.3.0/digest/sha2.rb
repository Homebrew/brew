# frozen_string_literal: false
#--
# sha2.rb - defines Digest::SHA2 class which wraps up the SHA256,
#           SHA384, and SHA512 classes.
#++
# Copyright (c) 2006 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.  You can redistribute and/or modify it under the same
# terms as Ruby.
#
#   $Id$

require 'digest'
require 'digest/sha2/loader'

module Digest
  #
  # A meta digest provider class for SHA256, SHA384 and SHA512.
  #
  # FIPS 180-2 describes SHA2 family of digest algorithms. It defines
  # three algorithms:
  # * one which works on chunks of 512 bits and returns a 256-bit
  #   digest (SHA256),
  # * one which works on chunks of 1024 bits and returns a 384-bit
  #   digest (SHA384),
  # * and one which works on chunks of 1024 bits and returns a 512-bit
  #   digest (SHA512).
  #
  # ==Examples
  #  require 'digest'
  #
  #  # Compute a complete digest
  #  Digest::SHA2.hexdigest 'abc'          # => "ba7816bf8..."
  #  Digest::SHA2.new(256).hexdigest 'abc' # => "ba7816bf8..."
  #  Digest::SHA256.hexdigest 'abc'        # => "ba7816bf8..."
  #
  #  Digest::SHA2.new(384).hexdigest 'abc' # => "cb00753f4..."
  #  Digest::SHA384.hexdigest 'abc'        # => "cb00753f4..."
  #
  #  Digest::SHA2.new(512).hexdigest 'abc' # => "ddaf35a19..."
  #  Digest::SHA512.hexdigest 'abc'        # => "ddaf35a19..."
  #
  #  # Compute digest by chunks
  #  sha2 = Digest::SHA2.new               # =>#<Digest::SHA2:256>
  #  sha2.update "ab"
  #  sha2 << "c"                           # alias for #update
  #  sha2.hexdigest                        # => "ba7816bf8..."
  #
  #  # Use the same object to compute another digest
  #  sha2.reset
  #  sha2 << "message"
  #  sha2.hexdigest                        # => "ab530a13e..."
  #
  class SHA2 < Digest::Class
    # call-seq:
    #   Digest::SHA2.new(bitlen = 256) -> digest_obj
    #
    # Create a new SHA2 hash object with a given bit length.
    #
    # Valid bit lengths are 256, 384 and 512.
    def initialize(bitlen = 256)
      case bitlen
      when 256
        @sha2 = Digest::SHA256.new
      when 384
        @sha2 = Digest::SHA384.new
      when 512
        @sha2 = Digest::SHA512.new
      else
        raise ArgumentError, "unsupported bit length: %s" % bitlen.inspect
      end
      @bitlen = bitlen
    end

    # call-seq:
    #   digest_obj.reset -> digest_obj
    #
    # Reset the digest to the initial state and return self.
    def reset
      @sha2.reset
      self
    end

    # call-seq:
    #   digest_obj.update(string) -> digest_obj
    #   digest_obj << string -> digest_obj
    #
    # Update the digest using a given _string_ and return self.
    def update(str)
      @sha2.update(str)
      self
    end
    alias << update

    def finish # :nodoc:
      @sha2.digest!
    end
    private :finish


    # call-seq:
    #   digest_obj.block_length -> Integer
    #
    # Return the block length of the digest in bytes.
    #
    #   Digest::SHA256.new.block_length * 8
    #   # => 512
    #   Digest::SHA384.new.block_length * 8
    #   # => 1024
    #   Digest::SHA512.new.block_length * 8
    #   # => 1024
    def block_length
      @sha2.block_length
    end

    # call-seq:
    #   digest_obj.digest_length -> Integer
    #
    # Return the length of the hash value (the digest) in bytes.
    #
    #   Digest::SHA256.new.digest_length * 8
    #   # => 256
    #   Digest::SHA384.new.digest_length * 8
    #   # => 384
    #   Digest::SHA512.new.digest_length * 8
    #   # => 512
    #
    # For example, digests produced by Digest::SHA256 will always be 32 bytes
    # (256 bits) in size.
    def digest_length
      @sha2.digest_length
    end

    def initialize_copy(other) # :nodoc:
      @sha2 = other.instance_eval { @sha2.clone }
    end

    def inspect # :nodoc:
      "#<%s:%d %s>" % [self.class.name, @bitlen, hexdigest]
    end
  end
end
