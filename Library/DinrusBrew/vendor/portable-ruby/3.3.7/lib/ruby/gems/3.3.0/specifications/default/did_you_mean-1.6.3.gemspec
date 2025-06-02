# -*- encoding: utf-8 -*-
# stub: did_you_mean 1.6.3 ruby lib

Gem::Specification.new do |s|
  s.name = "did_you_mean".freeze
  s.version = "1.6.3".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Yuki Nishijima".freeze]
  s.date = "2025-01-15"
  s.description = "The gem that has been saving people from typos since 2014.".freeze
  s.email = ["mail@yukinishijima.net".freeze]
  s.files = ["did_you_mean.rb".freeze, "did_you_mean/core_ext/name_error.rb".freeze, "did_you_mean/experimental.rb".freeze, "did_you_mean/formatter.rb".freeze, "did_you_mean/formatters/plain_formatter.rb".freeze, "did_you_mean/formatters/verbose_formatter.rb".freeze, "did_you_mean/jaro_winkler.rb".freeze, "did_you_mean/levenshtein.rb".freeze, "did_you_mean/spell_checker.rb".freeze, "did_you_mean/spell_checkers/key_error_checker.rb".freeze, "did_you_mean/spell_checkers/method_name_checker.rb".freeze, "did_you_mean/spell_checkers/name_error_checkers.rb".freeze, "did_you_mean/spell_checkers/name_error_checkers/class_name_checker.rb".freeze, "did_you_mean/spell_checkers/name_error_checkers/variable_name_checker.rb".freeze, "did_you_mean/spell_checkers/null_checker.rb".freeze, "did_you_mean/spell_checkers/pattern_key_name_checker.rb".freeze, "did_you_mean/spell_checkers/require_path_checker.rb".freeze, "did_you_mean/tree_spell_checker.rb".freeze, "did_you_mean/verbose.rb".freeze, "did_you_mean/version.rb".freeze]
  s.homepage = "https://github.com/ruby/did_you_mean".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "\"Did you mean?\" experience in Ruby".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
