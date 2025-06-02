# -*- encoding: utf-8 -*-
# stub: tmpdir 0.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "tmpdir".freeze
  s.version = "0.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/tmpdir", "source_code_uri" => "https://github.com/ruby/tmpdir" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Yukihiro Matsumoto".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "Extends the Dir class to manage the OS temporary file path.".freeze
  s.email = ["matz@ruby-lang.org".freeze]
  s.files = ["tmpdir.rb".freeze]
  s.homepage = "https://github.com/ruby/tmpdir".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Extends the Dir class to manage the OS temporary file path.".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<fileutils>.freeze, [">= 0".freeze])
end
