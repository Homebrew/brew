# -*- encoding: utf-8 -*-
# stub: net-pop 0.1.1 ruby lib

Gem::Specification.new do |s|
  s.name = "net-pop".freeze
  s.version = "0.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/net-pop", "source_code_uri" => "https://github.com/ruby/net-pop" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Yukihiro Matsumoto".freeze]
  s.bindir = "exe".freeze
  s.date = "2020-12-22"
  s.description = "Ruby client library for POP3.".freeze
  s.email = ["matz@ruby-lang.org".freeze]
  s.homepage = "https://github.com/ruby/net-pop".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Ruby client library for POP3.".freeze

  s.installed_by_version = "3.3.26" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<net-protocol>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<digest>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<timeout>.freeze, [">= 0"])
  else
    s.add_dependency(%q<net-protocol>.freeze, [">= 0"])
    s.add_dependency(%q<digest>.freeze, [">= 0"])
    s.add_dependency(%q<timeout>.freeze, [">= 0"])
  end
end
