# -*- encoding: utf-8 -*-
# stub: io-console 0.7.1 ruby lib
# stub: ext/io/console/extconf.rb

Gem::Specification.new do |s|
  s.name = "io-console".freeze
  s.version = "0.7.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "source_code_url" => "https://github.com/ruby/io-console" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Nobu Nakada".freeze]
  s.date = "2025-01-15"
  s.description = "add console capabilities to IO instances.".freeze
  s.email = "nobu@ruby-lang.org".freeze
  s.extensions = ["ext/io/console/extconf.rb".freeze]
  s.files = ["console/size.rb".freeze, "ext/io/console/extconf.rb".freeze, "io/console.so".freeze]
  s.homepage = "https://github.com/ruby/io-console".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Console interface".freeze
end
