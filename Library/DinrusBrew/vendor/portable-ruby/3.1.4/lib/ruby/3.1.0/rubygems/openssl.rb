# frozen_string_literal: true

autoload :OpenSSL, "openssl"

module Gem
  HAVE_OPENSSL = defined? OpenSSL::SSL # :nodoc:
end
