# -*- encoding: utf-8 -*-
# stub: readline-ext 0.1.4 ruby lib
# stub: ext/readline/extconf.rb

Gem::Specification.new do |s|
  s.name = "readline-ext".freeze
  s.version = "0.1.4"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/ruby/readline-ext", "source_code_uri" => "https://github.com/ruby/readline-ext" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Yukihiro Matsumoto".freeze]
  s.bindir = "exe".freeze
  s.date = "2023-03-30"
  s.description = "Provides an interface for GNU Readline and Edit Line (libedit).".freeze
  s.email = ["matz@ruby-lang.org".freeze]
  s.extensions = ["ext/readline/extconf.rb".freeze]
  s.files = ["ext/readline/extconf.rb".freeze]
  s.homepage = "https://github.com/ruby/readline-ext".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.rubygems_version = "3.3.26".freeze
  s.summary = "Provides an interface for GNU Readline and Edit Line (libedit).".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<rake-compiler>.freeze, [">= 0"])
  else
    s.add_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<rake-compiler>.freeze, [">= 0"])
  end
end
