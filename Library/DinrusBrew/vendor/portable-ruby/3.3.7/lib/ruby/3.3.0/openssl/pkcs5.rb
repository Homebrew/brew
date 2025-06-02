# frozen_string_literal: true
#--
# Ruby/OpenSSL Project
# Copyright (C) 2017 Ruby/OpenSSL Project Authors
#++

module OpenSSL
  module PKCS5
    module_function

    # OpenSSL::PKCS5.pbkdf2_hmac has been renamed to OpenSSL::KDF.pbkdf2_hmac.
    # This method is provided for backwards compatibility.
    def pbkdf2_hmac(pass, salt, iter, keylen, digest)
      OpenSSL::KDF.pbkdf2_hmac(pass, salt: salt, iterations: iter,
                               length: keylen, hash: digest)
    end

    def pbkdf2_hmac_sha1(pass, salt, iter, keylen)
      pbkdf2_hmac(pass, salt, iter, keylen, "sha1")
    end
  end
end
