# -*- encoding: utf-8 -*-
# stub: time 0.2.2 ruby lib

Gem::Specification.new do |s|
  s.name = "time".freeze
  s.version = "0.2.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/time", "source_code_uri" => "https://github.com/ruby/time" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Tanaka Akira".freeze]
  s.bindir = "exe".freeze
  s.date = "2023-03-30"
  s.description = "Extends the Time class with methods for parsing and conversion.".freeze
  s.email = ["akr@fsij.org".freeze]
  s.files = ["time.rb".freeze]
  s.homepage = "https://github.com/ruby/time".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Extends the Time class with methods for parsing and conversion.".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<date>.freeze, [">= 0"])
  else
    s.add_dependency(%q<date>.freeze, [">= 0"])
  end
end
