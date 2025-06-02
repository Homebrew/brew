# -*- encoding: utf-8 -*-
# stub: syslog 0.1.2 ruby lib
# stub: ext/syslog/extconf.rb

Gem::Specification.new do |s|
  s.name = "syslog".freeze
  s.version = "0.1.2".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/syslog", "source_code_uri" => "https://github.com/ruby/syslog" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Akinori MUSHA".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "Ruby interface for the POSIX system logging facility.".freeze
  s.email = ["knu@idaemons.org".freeze]
  s.extensions = ["ext/syslog/extconf.rb".freeze]
  s.files = ["ext/syslog/extconf.rb".freeze, "syslog.so".freeze, "syslog/logger.rb".freeze]
  s.homepage = "https://github.com/ruby/syslog".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Ruby interface for the POSIX system logging facility.".freeze
end
