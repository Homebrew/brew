# typed: strict
# frozen_string_literal: true

# These should not be made constants or Tapioca will think they are part of a gem.
dependency_require_map = {
  "ruby-macho" => "macho",
}.freeze

additional_requires_map = {
  "parser"        => ["parser/current"],
  "rubocop-rspec" => ["rubocop/rspec/expect_offense"],
}.freeze

# Freeze lockfile
Bundler.settings.set_command_option(:frozen, "1")

definition = Bundler.definition
definition.resolve.for(definition.current_dependencies).each do |spec|
  name = spec.name

  # These sorbet gems do not contain any library files
  next if name == "sorbet"
  next if name == "sorbet-static"
  next if name == "sorbet-static-and-runtime"

  name = dependency_require_map[name] if dependency_require_map.key?(name)
  require name
  additional_requires_map[name]&.each { require(_1) }
rescue LoadError
  raise unless name.include?("-")

  name = name.tr("-", "/")
  require name
end
