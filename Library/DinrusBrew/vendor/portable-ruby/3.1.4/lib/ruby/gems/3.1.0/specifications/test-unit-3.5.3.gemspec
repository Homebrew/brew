# -*- encoding: utf-8 -*-
# stub: test-unit 3.5.3 ruby lib

Gem::Specification.new do |s|
  s.name = "test-unit".freeze
  s.version = "3.5.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/test-unit/test-unit/issues", "documentation_uri" => "https://test-unit.github.io/test-unit/en/", "source_code_uri" => "https://github.com/test-unit/test-unit" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Kouhei Sutou".freeze, "Haruka Yoshihara".freeze]
  s.date = "2021-12-19"
  s.description = "test-unit (Test::Unit) is unit testing framework for Ruby, based on xUnit\nprinciples. These were originally designed by Kent Beck, creator of extreme\nprogramming software development methodology, for Smalltalk's SUnit. It allows\nwriting tests, checking results and automated testing in Ruby.\n".freeze
  s.email = ["kou@cozmixng.org".freeze, "yoshihara@clear-code.com".freeze]
  s.homepage = "http://test-unit.github.io/".freeze
  s.licenses = ["Ruby".freeze, "BSDL".freeze, "PSFL".freeze]
  s.rubygems_version = "3.3.26".freeze
  s.summary = "An xUnit family unit testing framework for Ruby.".freeze

  s.installed_by_version = "3.3.26" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_runtime_dependency(%q<power_assert>.freeze, [">= 0"])
    s.add_development_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_development_dependency(%q<yard>.freeze, [">= 0"])
    s.add_development_dependency(%q<kramdown>.freeze, [">= 0"])
    s.add_development_dependency(%q<packnga>.freeze, [">= 0"])
  else
    s.add_dependency(%q<power_assert>.freeze, [">= 0"])
    s.add_dependency(%q<bundler>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<yard>.freeze, [">= 0"])
    s.add_dependency(%q<kramdown>.freeze, [">= 0"])
    s.add_dependency(%q<packnga>.freeze, [">= 0"])
  end
end
