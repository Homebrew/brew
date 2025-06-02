# -*- encoding: utf-8 -*-
# stub: io-wait 0.3.1 ruby lib
# stub: ext/io/wait/extconf.rb

Gem::Specification.new do |s|
  s.name = "io-wait".freeze
  s.version = "0.3.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/io-wait", "source_code_uri" => "https://github.com/ruby/io-wait" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Nobu Nakada".freeze, "Charles Oliver Nutter".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "Waits until IO is readable or writable without blocking.".freeze
  s.email = ["nobu@ruby-lang.org".freeze, "headius@headius.com".freeze]
  s.extensions = ["ext/io/wait/extconf.rb".freeze]
  s.files = ["ext/io/wait/extconf.rb".freeze, "io/wait.so".freeze]
  s.homepage = "https://github.com/ruby/io-wait".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Waits until IO is readable or writable without blocking.".freeze
end
