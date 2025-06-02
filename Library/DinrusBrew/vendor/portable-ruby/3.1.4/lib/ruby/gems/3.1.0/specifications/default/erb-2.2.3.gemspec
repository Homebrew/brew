# -*- encoding: utf-8 -*-
# stub: erb 2.2.3 ruby lib

Gem::Specification.new do |s|
  s.name = "erb".freeze
  s.version = "2.2.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/erb", "source_code_uri" => "https://github.com/ruby/erb" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Masatoshi SEKI".freeze]
  s.bindir = "libexec".freeze
  s.date = "2023-03-30"
  s.description = "An easy to use but powerful templating system for Ruby.".freeze
  s.email = ["seki@ruby-lang.org".freeze]
  s.executables = ["erb".freeze]
  s.files = ["erb.rb".freeze, "libexec/erb".freeze]
  s.homepage = "https://github.com/ruby/erb".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "An easy to use but powerful templating system for Ruby.".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<cgi>.freeze, [">= 0"])
  else
    s.add_dependency(%q<cgi>.freeze, [">= 0"])
  end
end
