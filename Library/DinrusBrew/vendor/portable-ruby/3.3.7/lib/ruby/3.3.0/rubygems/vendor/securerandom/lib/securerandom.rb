# -*- coding: us-ascii -*-
# frozen_string_literal: true

require_relative 'random/formatter'

# == Secure random number generator interface.
#
# This library is an interface to secure random number generators which are
# suitable for generating session keys in HTTP cookies, etc.
#
# You can use this library in your application by requiring it:
#
#   require 'rubygems/vendor/securerandom/lib/securerandom'
#
# It supports the following secure random number generators:
#
# * openssl
# * /dev/urandom
# * Win32
#
# Gem::SecureRandom is extended by the Gem::Random::Formatter module which
# defines the following methods:
#
# * alphanumeric
# * base64
# * choose
# * gen_random
# * hex
# * rand
# * random_bytes
# * random_number
# * urlsafe_base64
# * uuid
#
# These methods are usable as class methods of Gem::SecureRandom such as
# +Gem::SecureRandom.hex+.
#
# If a secure random number generator is not available,
# +NotImplementedError+ is raised.

module Gem::SecureRandom

  # The version
  VERSION = "0.3.1"

  class << self
    # Returns a random binary string containing +size+ bytes.
    #
    # See Random.bytes
    def bytes(n)
      return gen_random(n)
    end

    private

    # :stopdoc:

    # Implementation using OpenSSL
    def gen_random_openssl(n)
      return OpenSSL::Random.random_bytes(n)
    end

    # Implementation using system random device
    def gen_random_urandom(n)
      ret = Random.urandom(n)
      unless ret
        raise NotImplementedError, "No random device"
      end
      unless ret.length == n
        raise NotImplementedError, "Unexpected partial read from random device: only #{ret.length} for #{n} bytes"
      end
      ret
    end

    begin
      # Check if Random.urandom is available
      Random.urandom(1)
      alias gen_random gen_random_urandom
    rescue RuntimeError
      begin
        require 'openssl'
      rescue NoMethodError
        raise NotImplementedError, "No random device"
      else
        alias gen_random gen_random_openssl
      end
    end

    # :startdoc:

    # Generate random data bytes for Gem::Random::Formatter
    public :gen_random
  end
end

Gem::SecureRandom.extend(Gem::Random::Formatter)
