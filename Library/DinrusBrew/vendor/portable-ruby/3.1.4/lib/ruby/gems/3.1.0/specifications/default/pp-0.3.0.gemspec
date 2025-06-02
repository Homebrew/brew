# -*- encoding: utf-8 -*-
# stub: pp 0.3.0 ruby lib

Gem::Specification.new do |s|
  s.name = "pp".freeze
  s.version = "0.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/pp", "source_code_uri" => "https://github.com/ruby/pp" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Tanaka Akira".freeze]
  s.bindir = "exe".freeze
  s.date = "2023-03-30"
  s.description = "Provides a PrettyPrinter for Ruby objects".freeze
  s.email = ["akr@fsij.org".freeze]
  s.files = ["pp.rb".freeze]
  s.homepage = "https://github.com/ruby/pp".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Provides a PrettyPrinter for Ruby objects".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<prettyprint>.freeze, [">= 0"])
  else
    s.add_dependency(%q<prettyprint>.freeze, [">= 0"])
  end
end
