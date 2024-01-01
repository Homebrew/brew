# typed: strict
# frozen_string_literal: true

# This should not be made a constant or Tapioca will think it is part of a gem.
dependency_require_map = {
  "activesupport" => "active_support/all",
  "ruby-macho"    => "macho",
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
rescue LoadError
  raise unless name.include?("-")

  name = name.tr("-", "/")
  require name
end
