# -*- encoding: utf-8 -*-
# stub: drb 2.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "drb".freeze
  s.version = "2.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/drb", "source_code_uri" => "https://github.com/ruby/drb" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Masatoshi SEKI".freeze]
  s.date = "2025-01-15"
  s.description = "Distributed object system for Ruby".freeze
  s.email = ["seki@ruby-lang.org".freeze]
  s.files = ["drb.rb".freeze, "drb/acl.rb".freeze, "drb/drb.rb".freeze, "drb/eq.rb".freeze, "drb/extserv.rb".freeze, "drb/extservm.rb".freeze, "drb/gw.rb".freeze, "drb/invokemethod.rb".freeze, "drb/observer.rb".freeze, "drb/ssl.rb".freeze, "drb/timeridconv.rb".freeze, "drb/unix.rb".freeze, "drb/version.rb".freeze, "drb/weakidconv.rb".freeze]
  s.homepage = "https://github.com/ruby/drb".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Distributed object system for Ruby".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<ruby2_keywords>.freeze, [">= 0".freeze])
end
