# -*- encoding: utf-8 -*-
# stub: csv 3.2.8 ruby lib

Gem::Specification.new do |s|
  s.name = "csv".freeze
  s.version = "3.2.8".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["James Edward Gray II".freeze, "Kouhei Sutou".freeze]
  s.date = "2025-01-15"
  s.description = "The CSV library provides a complete interface to CSV files and data. It offers tools to enable you to read and write to and from Strings or IO objects, as needed.".freeze
  s.email = [nil, "kou@cozmixng.org".freeze]
  s.extra_rdoc_files = ["LICENSE.txt".freeze, "NEWS.md".freeze, "README.md".freeze]
  s.files = ["LICENSE.txt".freeze, "NEWS.md".freeze, "README.md".freeze, "csv.rb".freeze, "csv/core_ext/array.rb".freeze, "csv/core_ext/string.rb".freeze, "csv/fields_converter.rb".freeze, "csv/input_record_separator.rb".freeze, "csv/parser.rb".freeze, "csv/row.rb".freeze, "csv/table.rb".freeze, "csv/version.rb".freeze, "csv/writer.rb".freeze]
  s.homepage = "https://github.com/ruby/csv".freeze
  s.licenses = ["Ruby".freeze, "BSD-2-Clause".freeze]
  s.rdoc_options = ["--main".freeze, "README.md".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "CSV Reading and Writing".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<benchmark_driver>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<test-unit>.freeze, [">= 3.4.8".freeze])
end
