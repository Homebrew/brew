# -*- encoding: utf-8 -*-
# stub: open-uri 0.4.1 ruby lib

Gem::Specification.new do |s|
  s.name = "open-uri".freeze
  s.version = "0.4.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/open-uri", "source_code_uri" => "https://github.com/ruby/open-uri" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Tanaka Akira".freeze]
  s.date = "2025-01-15"
  s.description = "An easy-to-use wrapper for Net::HTTP, Net::HTTPS and Net::FTP.".freeze
  s.email = ["akr@fsij.org".freeze]
  s.files = ["open-uri.rb".freeze]
  s.homepage = "https://github.com/ruby/open-uri".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "An easy-to-use wrapper for Net::HTTP, Net::HTTPS and Net::FTP.".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<uri>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<stringio>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<time>.freeze, [">= 0".freeze])
end
