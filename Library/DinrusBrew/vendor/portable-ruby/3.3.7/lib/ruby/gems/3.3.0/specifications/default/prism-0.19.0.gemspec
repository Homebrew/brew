# -*- encoding: utf-8 -*-
# stub: prism 0.19.0 ruby lib
# stub: ext/prism/extconf.rb

Gem::Specification.new do |s|
  s.name = "prism".freeze
  s.version = "0.19.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.org", "changelog_uri" => "https://github.com/ruby/prism/blob/main/CHANGELOG.md", "source_code_uri" => "https://github.com/ruby/prism" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Shopify".freeze]
  s.date = "2025-01-15"
  s.email = ["ruby@shopify.com".freeze]
  s.extensions = ["ext/prism/extconf.rb".freeze]
  s.files = ["ext/prism/extconf.rb".freeze, "prism.rb".freeze, "prism/compiler.rb".freeze, "prism/debug.rb".freeze, "prism/desugar_compiler.rb".freeze, "prism/dispatcher.rb".freeze, "prism/dsl.rb".freeze, "prism/ffi.rb".freeze, "prism/lex_compat.rb".freeze, "prism/mutation_compiler.rb".freeze, "prism/node.rb".freeze, "prism/node_ext.rb".freeze, "prism/node_inspector.rb".freeze, "prism/pack.rb".freeze, "prism/parse_result.rb".freeze, "prism/parse_result/comments.rb".freeze, "prism/parse_result/newlines.rb".freeze, "prism/pattern.rb".freeze, "prism/ripper_compat.rb".freeze, "prism/serialize.rb".freeze, "prism/visitor.rb".freeze]
  s.homepage = "https://github.com/ruby/prism".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.0.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Prism Ruby parser".freeze
end
