# -*- encoding: utf-8 -*-
# stub: rinda 0.1.1 ruby lib

Gem::Specification.new do |s|
  s.name = "rinda".freeze
  s.version = "0.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/rinda", "source_code_uri" => "https://github.com/ruby/rinda" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Masatoshi SEKI".freeze]
  s.bindir = "exe".freeze
  s.date = "2023-03-30"
  s.description = "The Linda distributed computing paradigm in Ruby.".freeze
  s.email = ["seki@ruby-lang.org".freeze]
  s.files = ["lib/rinda/rinda.rb".freeze, "lib/rinda/ring.rb".freeze, "lib/rinda/tuplespace.rb".freeze]
  s.homepage = "https://github.com/ruby/rinda".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "The Linda distributed computing paradigm in Ruby.".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<drb>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<ipaddr>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<forwardable>.freeze, [">= 0"])
  else
    s.add_dependency(%q<drb>.freeze, [">= 0"])
    s.add_dependency(%q<ipaddr>.freeze, [">= 0"])
    s.add_dependency(%q<forwardable>.freeze, [">= 0"])
  end
end
