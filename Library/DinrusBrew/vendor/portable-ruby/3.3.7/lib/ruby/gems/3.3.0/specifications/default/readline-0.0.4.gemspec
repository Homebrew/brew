# -*- encoding: utf-8 -*-
# stub: readline 0.0.4 ruby lib

Gem::Specification.new do |s|
  s.name = "readline".freeze
  s.version = "0.0.4".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["aycabta".freeze]
  s.date = "2025-01-15"
  s.description = "This is just a loader for \"readline\". If Ruby has the \"readline-ext\" gem\nthat is a native extension, this gem will load it. If Ruby does not have\nthe \"readline-ext\" gem this gem will load \"reline\", a library that is\ncompatible with the \"readline-ext\" gem and implemented in pure Ruby.\n".freeze
  s.email = ["aycabta@gmail.com".freeze]
  s.files = ["readline.rb".freeze]
  s.homepage = "https://github.com/ruby/readline".freeze
  s.licenses = ["Ruby".freeze]
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Loader for \"readline\".".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<reline>.freeze, [">= 0".freeze])
end
