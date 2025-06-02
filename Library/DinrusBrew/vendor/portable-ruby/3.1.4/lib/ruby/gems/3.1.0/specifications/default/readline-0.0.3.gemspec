# -*- encoding: utf-8 -*-
# stub: readline 0.0.3 ruby lib

Gem::Specification.new do |s|
  s.name = "readline".freeze
  s.version = "0.0.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["aycabta".freeze]
  s.date = "2023-03-30"
  s.description = "This is just a loader for \"readline\". If Ruby has the \"readline-ext\" gem\nthat is a native extension, this gem will load it. If Ruby does not have\nthe \"readline-ext\" gem this gem will load \"reline\", a library that is\ncompatible with the \"readline-ext\" gem and implemented in pure Ruby.\n".freeze
  s.email = ["aycabta@gmail.com".freeze]
  s.files = ["readline.rb".freeze]
  s.homepage = "https://github.com/ruby/readline".freeze
  s.licenses = ["Ruby".freeze]
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Loader for \"readline\".".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<reline>.freeze, [">= 0"])
  else
    s.add_dependency(%q<reline>.freeze, [">= 0"])
  end
end
