# -*- encoding: utf-8 -*-
# stub: cgi 0.3.6 ruby lib
# stub: ext/cgi/escape/extconf.rb

Gem::Specification.new do |s|
  s.name = "cgi".freeze
  s.version = "0.3.6"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/cgi", "source_code_uri" => "https://github.com/ruby/cgi" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Yukihiro Matsumoto".freeze]
  s.date = "2023-03-30"
  s.description = "Support for the Common Gateway Interface protocol.".freeze
  s.email = ["matz@ruby-lang.org".freeze]
  s.extensions = ["ext/cgi/escape/extconf.rb".freeze]
  s.files = ["ext/cgi/escape/extconf.rb".freeze, "lib/cgi.rb".freeze, "lib/cgi/cookie.rb".freeze, "lib/cgi/core.rb".freeze, "lib/cgi/html.rb".freeze, "lib/cgi/session.rb".freeze, "lib/cgi/session/pstore.rb".freeze, "lib/cgi/util.rb".freeze]
  s.homepage = "https://github.com/ruby/cgi".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Support for the Common Gateway Interface protocol.".freeze
end
