# -*- encoding: utf-8 -*-
# stub: openssl 3.2.0 ruby lib
# stub: ext/openssl/extconf.rb

Gem::Specification.new do |s|
  s.name = "openssl".freeze
  s.version = "3.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "msys2_mingw_dependencies" => "openssl" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Martin Bosslet".freeze, "SHIBATA Hiroshi".freeze, "Zachary Scott".freeze, "Kazuki Yamaguchi".freeze]
  s.date = "2025-01-15"
  s.description = "OpenSSL for Ruby provides access to SSL/TLS and general-purpose cryptography based on the OpenSSL library.".freeze
  s.email = ["ruby-core@ruby-lang.org".freeze]
  s.extensions = ["ext/openssl/extconf.rb".freeze]
  s.extra_rdoc_files = ["CONTRIBUTING.md".freeze, "NEWS.md".freeze, "README.ja.md".freeze, "README.md".freeze]
  s.files = ["CONTRIBUTING.md".freeze, "NEWS.md".freeze, "README.ja.md".freeze, "README.md".freeze, "ext/openssl/extconf.rb".freeze, "openssl.rb".freeze, "openssl.so".freeze, "openssl/bn.rb".freeze, "openssl/buffering.rb".freeze, "openssl/cipher.rb".freeze, "openssl/digest.rb".freeze, "openssl/hmac.rb".freeze, "openssl/marshal.rb".freeze, "openssl/pkcs5.rb".freeze, "openssl/pkey.rb".freeze, "openssl/ssl.rb".freeze, "openssl/version.rb".freeze, "openssl/x509.rb".freeze]
  s.homepage = "https://github.com/ruby/openssl".freeze
  s.licenses = ["Ruby".freeze]
  s.rdoc_options = ["--main".freeze, "README.md".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "SSL/TLS and general-purpose cryptography for Ruby".freeze
end
