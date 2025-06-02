# -*- coding: us-ascii -*-
# frozen_string_literal: true

require 'random/formatter'

# == Secure random number generator interface.
#
# This library is an interface to secure random number generators which are
# suitable for generating session keys in HTTP cookies, etc.
#
# You can use this library in your application by requiring it:
#
#   require 'securerandom'
#
# It supports the following secure random number generators:
#
# * openssl
# * /dev/urandom
# * Win32
#
# SecureRandom is extended by the Random::Formatter module which
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
# These methods are usable as class methods of SecureRandom such as
# +SecureRandom.hex+.
#
# If a secure random number generator is not available,
# +NotImplementedError+ is raised.

module SecureRandom
  class << self
    def bytes(n)
      return gen_random(n)
    end

    private

    def gen_random_openssl(n)
      @pid = 0 unless defined?(@pid)
      pid = $$
      unless @pid == pid
        now = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
        OpenSSL::Random.random_add([now, @pid, pid].join(""), 0.0)
        seed = Random.urandom(16)
        if (seed)
          OpenSSL::Random.random_add(seed, 16)
        end
        @pid = pid
      end
      return OpenSSL::Random.random_bytes(n)
    end

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

    ret = Random.urandom(1)
    if ret.nil?
      begin
        require 'openssl'
      rescue NoMethodError
        raise NotImplementedError, "No random device"
      else
        alias gen_random gen_random_openssl
      end
    else
      alias gen_random gen_random_urandom
    end

    public :gen_random
  end
end

SecureRandom.extend(Random::Formatter)
