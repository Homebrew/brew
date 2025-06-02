# -*- encoding: utf-8 -*-
# stub: net-smtp 0.3.1 ruby lib

Gem::Specification.new do |s|
  s.name = "net-smtp".freeze
  s.version = "0.3.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/net-smtp", "source_code_uri" => "https://github.com/ruby/net-smtp" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Yukihiro Matsumoto".freeze]
  s.date = "2021-12-12"
  s.description = "Simple Mail Transfer Protocol client library for Ruby.".freeze
  s.email = ["matz@ruby-lang.org".freeze]
  s.homepage = "https://github.com/ruby/net-smtp".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Simple Mail Transfer Protocol client library for Ruby.".freeze

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
