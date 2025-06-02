# -*- encoding: utf-8 -*-
# stub: bootsnap 1.18.4 ruby lib
# stub: ext/bootsnap/extconf.rb

Gem::Specification.new do |s|
  s.name = "bootsnap".freeze
  s.version = "1.18.4".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.org", "bug_tracker_uri" => "https://github.com/Shopify/bootsnap/issues", "changelog_uri" => "https://github.com/Shopify/bootsnap/blob/main/CHANGELOG.md", "source_code_uri" => "https://github.com/Shopify/bootsnap" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Burke Libbey".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-15"
  s.description = "Boot large ruby/rails apps faster".freeze
  s.email = ["burke.libbey@shopify.com".freeze]
  s.executables = ["bootsnap".freeze]
  s.extensions = ["ext/bootsnap/extconf.rb".freeze]
  s.files = ["exe/bootsnap".freeze, "ext/bootsnap/extconf.rb".freeze]
  s.homepage = "https://github.com/Shopify/bootsnap".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.6.0".freeze)
  s.rubygems_version = "3.5.16".freeze
  s.summary = "Boot large ruby/rails apps faster".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<msgpack>.freeze, ["~> 1.2".freeze])
end
