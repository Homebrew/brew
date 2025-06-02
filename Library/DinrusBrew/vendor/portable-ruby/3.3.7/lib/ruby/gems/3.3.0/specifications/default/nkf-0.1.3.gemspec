# -*- encoding: utf-8 -*-
# stub: nkf 0.1.3 ruby lib
# stub: ext/nkf/extconf.rb

Gem::Specification.new do |s|
  s.name = "nkf".freeze
  s.version = "0.1.3".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/nkf", "source_code_uri" => "https://github.com/ruby/nkf" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["NARUSE Yui".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "Ruby extension for Network Kanji Filter".freeze
  s.email = ["naruse@airemix.jp".freeze]
  s.extensions = ["ext/nkf/extconf.rb".freeze]
  s.files = ["ext/nkf/extconf.rb".freeze, "kconv.rb".freeze, "nkf.so".freeze]
  s.homepage = "https://github.com/ruby/nkf".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Ruby extension for Network Kanji Filter".freeze
end
