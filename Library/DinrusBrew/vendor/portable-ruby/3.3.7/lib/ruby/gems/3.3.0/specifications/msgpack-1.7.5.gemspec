# -*- encoding: utf-8 -*-
# stub: msgpack 1.7.5 ruby lib
# stub: ext/msgpack/extconf.rb

Gem::Specification.new do |s|
  s.name = "msgpack".freeze
  s.version = "1.7.5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Sadayuki Furuhashi".freeze, "Theo Hultberg".freeze, "Satoshi Tagomori".freeze]
  s.date = "2025-01-15"
  s.description = "MessagePack is a binary-based efficient object serialization library. It enables to exchange structured objects between many languages like JSON. But unlike JSON, it is very fast and small.".freeze
  s.email = ["frsyuki@gmail.com".freeze, "theo@iconara.net".freeze, "tagomoris@gmail.com".freeze]
  s.extensions = ["ext/msgpack/extconf.rb".freeze]
  s.files = ["ext/msgpack/extconf.rb".freeze]
  s.homepage = "http://msgpack.org/".freeze
  s.licenses = ["Apache 2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "MessagePack, a binary-based efficient data interchange format.".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake-compiler>.freeze, [">= 1.1.9".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.3".freeze])
  s.add_development_dependency(%q<ruby_memcheck>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<yard>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<json>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<benchmark-ips>.freeze, ["~> 2.10.0".freeze])
end
