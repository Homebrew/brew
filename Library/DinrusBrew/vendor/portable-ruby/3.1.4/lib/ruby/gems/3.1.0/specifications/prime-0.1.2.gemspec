# -*- encoding: utf-8 -*-
# stub: prime 0.1.2 ruby lib

Gem::Specification.new do |s|
  s.name = "prime".freeze
  s.version = "0.1.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Marc-Andre Lafortune".freeze]
  s.bindir = "exe".freeze
  s.date = "2020-12-09"
  s.description = "Prime numbers and factorization library.".freeze
  s.email = ["ruby-core@marc-andre.ca".freeze]
  s.homepage = "https://github.com/ruby/prime".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Prime numbers and factorization library.".freeze

  s.installed_by_version = "3.3.26" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<singleton>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<forwardable>.freeze, [">= 0"])
  else
    s.add_dependency(%q<singleton>.freeze, [">= 0"])
    s.add_dependency(%q<forwardable>.freeze, [">= 0"])
  end
end
