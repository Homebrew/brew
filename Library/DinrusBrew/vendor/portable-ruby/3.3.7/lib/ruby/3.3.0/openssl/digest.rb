# frozen_string_literal: true
#--
# = Ruby-space predefined Digest subclasses
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
  class Digest

    # Return the hash value computed with _name_ Digest. _name_ is either the
    # long name or short name of a supported digest algorithm.
    #
    # === Example
    #
    #   OpenSSL::Digest.digest("SHA256", "abc")

    def self.digest(name, data)
      super(data, name)
    end

    %w(MD4 MD5 RIPEMD160 SHA1 SHA224 SHA256 SHA384 SHA512).each do |name|
      klass = Class.new(self) {
        define_method(:initialize, ->(data = nil) {super(name, data)})
      }

      singleton = (class << klass; self; end)

      singleton.class_eval{
        define_method(:digest) {|data| new.digest(data)}
        define_method(:hexdigest) {|data| new.hexdigest(data)}
      }

      const_set(name.tr('-', '_'), klass)
    end

    # Deprecated.
    #
    # This class is only provided for backwards compatibility.
    # Use OpenSSL::Digest instead.
    class Digest < Digest; end # :nodoc:
    deprecate_constant :Digest

  end # Digest

  # Returns a Digest subclass by _name_
  #
  #   require 'openssl'
  #
  #   OpenSSL::Digest("MD5")
  #   # => OpenSSL::Digest::MD5
  #
  #   Digest("Foo")
  #   # => NameError: wrong constant name Foo

  def Digest(name)
    OpenSSL::Digest.const_get(name)
  end

  module_function :Digest

end # OpenSSL
