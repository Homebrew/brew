# -*- encoding: utf-8 -*-
# stub: cgi 0.4.1 ruby lib
# stub: ext/cgi/escape/extconf.rb

Gem::Specification.new do |s|
  s.name = "cgi".freeze
  s.version = "0.4.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/cgi", "source_code_uri" => "https://github.com/ruby/cgi" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Yukihiro Matsumoto".freeze]
  s.date = "2025-01-15"
  s.description = "Support for the Common Gateway Interface protocol.".freeze
  s.email = ["matz@ruby-lang.org".freeze]
  s.extensions = ["ext/cgi/escape/extconf.rb".freeze]
  s.files = ["cgi.rb".freeze, "cgi/cookie.rb".freeze, "cgi/core.rb".freeze, "cgi/escape.so".freeze, "cgi/html.rb".freeze, "cgi/session.rb".freeze, "cgi/session/pstore.rb".freeze, "cgi/util.rb".freeze, "ext/cgi/escape/extconf.rb".freeze]
  s.homepage = "https://github.com/ruby/cgi".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Support for the Common Gateway Interface protocol.".freeze
end
