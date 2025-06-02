# frozen_string_literal: true
#--
# = Ruby-space predefined Cipher subclasses
#
# = Info
# 'OpenSSL for Ruby 2' project
# Copyright (C) 2002  Michal Rokos <m.rokos@sh.cvut.cz>
# All rights reserved.
#
# = Licence
# This program is licensed under the same licence as Ruby.
# (See the file 'LICENCE'.)
#++

module OpenSSL
  class Cipher
    %w(AES CAST5 BF DES IDEA RC2 RC4 RC5).each{|name|
      klass = Class.new(Cipher){
        define_method(:initialize){|*args|
          cipher_name = args.inject(name){|n, arg| "#{n}-#{arg}" }
          super(cipher_name.downcase)
        }
      }
      const_set(name, klass)
    }

    %w(128 192 256).each{|keylen|
      klass = Class.new(Cipher){
        define_method(:initialize){|mode = "CBC"|
          super("aes-#{keylen}-#{mode}".downcase)
        }
      }
      const_set("AES#{keylen}", klass)
    }

    # call-seq:
    #   cipher.random_key -> key
    #
    # Generate a random key with OpenSSL::Random.random_bytes and sets it to
    # the cipher, and returns it.
    #
    # You must call #encrypt or #decrypt before calling this method.
    def random_key
      str = OpenSSL::Random.random_bytes(self.key_len)
      self.key = str
    end

    # call-seq:
    #   cipher.random_iv -> iv
    #
    # Generate a random IV with OpenSSL::Random.random_bytes and sets it to the
    # cipher, and returns it.
    #
    # You must call #encrypt or #decrypt before calling this method.
    def random_iv
      str = OpenSSL::Random.random_bytes(self.iv_len)
      self.iv = str
    end

    # Deprecated.
    #
    # This class is only provided for backwards compatibility.
    # Use OpenSSL::Cipher.
    class Cipher < Cipher; end
    deprecate_constant :Cipher
  end # Cipher
end # OpenSSL
