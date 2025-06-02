# -*- encoding: utf-8 -*-
# stub: mutex_m 0.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "mutex_m".freeze
  s.version = "0.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Keiju ISHITSUKA".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "Mixin to extend objects to be handled like a Mutex.".freeze
  s.email = ["keiju@ruby-lang.org".freeze]
  s.files = ["mutex_m.rb".freeze]
  s.homepage = "https://github.com/ruby/mutex_m".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Mixin to extend objects to be handled like a Mutex.".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<test-unit>.freeze, [">= 0".freeze])
end
