# -*- encoding: utf-8 -*-
# stub: stringio 3.1.1 ruby lib
# stub: ext/stringio/extconf.rb

Gem::Specification.new do |s|
  s.name = "stringio".freeze
  s.version = "3.1.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Nobu Nakada".freeze, "Charles Oliver Nutter".freeze]
  s.date = "2025-01-15"
  s.description = "Pseudo `IO` class from/to `String`.".freeze
  s.email = ["nobu@ruby-lang.org".freeze, "headius@headius.com".freeze]
  s.extensions = ["ext/stringio/extconf.rb".freeze]
  s.files = ["ext/stringio/extconf.rb".freeze, "stringio.so".freeze]
  s.homepage = "https://github.com/ruby/stringio".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Pseudo IO on String".freeze
end
