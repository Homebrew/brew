# frozen_string_literal: true

require_relative "../command"
require_relative "../local_remote_options"
require_relative "../version_option"

class Gem::Commands::DependencyCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    super "dependency",
          "Show the dependencies of an installed gem",
          version: Gem::Requirement.default, domain: :local

    add_version_option
    add_platform_option
    add_prerelease_option

    add_option("-R", "--[no-]reverse-dependencies",
               "Include reverse dependencies in the output") do |value, options|
      options[:reverse_dependencies] = value
    end

    add_option("-p", "--pipe",
               "Pipe Format (name --version ver)") do |value, options|
      options[:pipe_format] = value
    end

    add_local_remote_options
  end

  def arguments # :nodoc:
    "REGEXP        show dependencies for gems whose names start with REGEXP"
  end

  def defaults_str # :nodoc:
    "--local --version '#{Gem::Requirement.default}' --no-reverse-dependencies"
  end

  def description # :nodoc:
    <<-EOF
The dependency commands lists which other gems a given gem depends on.  For
local gems only the reverse dependencies can be shown (which gems depend on
the named gem).

The dependency list can be displayed in a format suitable for piping for
use with other commands.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} REGEXP"
  end

  def fetch_remote_specs(name, requirement, prerelease) # :nodoc:
    fetcher = Gem::SpecFetcher.fetcher

    specs_type = prerelease ? :complete : :released

    ss = if name.nil?
      fetcher.detect(specs_type) { true }
    else
      fetcher.detect(specs_type) do |name_tuple|
        name === name_tuple.name && requirement.satisfied_by?(name_tuple.version)
      end
    end

    ss.map {|tuple, source| source.fetch_spec(tuple) }
  end

  def fetch_specs(name_pattern, requirement, prerelease) # :nodoc:
    specs = []

    if local?
      specs.concat Gem::Specification.stubs.find_all {|spec|
        name_matches = name_pattern ? name_pattern =~ spec.name : true
        version_matches = requirement.satisfied_by?(spec.version)

        name_matches && version_matches
      }.map(&:to_spec)
    end

    specs.concat fetch_remote_specs name_pattern, requirement, prerelease if remote?

    ensure_specs specs

    specs.uniq.sort
  end

  def display_pipe(specs) # :nodoc:
    specs.each do |spec|
      next if spec.dependencies.empty?
      spec.dependencies.sort_by(&:name).each do |dep|
        say "#{dep.name} --version '#{dep.requirement}'"
      end
    end
  end

  def display_readable(specs, reverse) # :nodoc:
    response = String.new

    specs.each do |spec|
      response << print_dependencies(spec)
      unless reverse[spec.full_name].empty?
        response << "  Used by\n"
        reverse[spec.full_name].each do |sp, dep|
          response << "    #{sp} (#{dep})\n"
        end
      end
      response << "\n"
    end

    say response
  end

  def execute
    ensure_local_only_reverse_dependencies

    pattern = name_pattern options[:args]
    requirement = Gem::Requirement.new options[:version]

    specs = fetch_specs pattern, requirement, options[:prerelease]

    reverse = reverse_dependencies specs

    if options[:pipe_format]
      display_pipe specs
    else
      display_readable specs, reverse
    end
  end

  def ensure_local_only_reverse_dependencies # :nodoc:
    if options[:reverse_dependencies] && remote? && !local?
      alert_error "Only reverse dependencies for local gems are supported."
      terminate_interaction 1
    end
  end

  def ensure_specs(specs) # :nodoc:
    return unless specs.empty?

    patterns = options[:args].join ","
    say "No gems found matching #{patterns} (#{options[:version]})" if
      Gem.configuration.verbose

    terminate_interaction 1
  end

  def print_dependencies(spec, level = 0) # :nodoc:
    response = String.new
    response << "  " * level + "Gem #{spec.full_name}\n"
    unless spec.dependencies.empty?
      spec.dependencies.sort_by(&:name).each do |dep|
        response << "  " * level + "  #{dep}\n"
      end
    end
    response
  end

  def reverse_dependencies(specs) # :nodoc:
    reverse = Hash.new {|h, k| h[k] = [] }

    return reverse unless options[:reverse_dependencies]

    specs.each do |spec|
      reverse[spec.full_name] = find_reverse_dependencies spec
    end

    reverse
  end

  ##
  # Returns an Array of [specification, dep] that are satisfied by +spec+.

  def find_reverse_dependencies(spec) # :nodoc:
    result = []

    Gem::Specification.each do |sp|
      sp.dependencies.each do |dep|
        dep = Gem::Dependency.new(*dep) unless Gem::Dependency === dep

        if spec.name == dep.name &&
           dep.requirement.satisfied_by?(spec.version)
          result << [sp.full_name, dep]
        end
      end
    end

    result
  end

  private

  def name_pattern(args)
    return if args.empty?

    if args.length == 1 && args.first =~ /\A(.*)(i)?\z/m
      flags = $2 ? Regexp::IGNORECASE : nil
      Regexp.new $1, flags
    else
      /\A#{Regexp.union(*args)}/
    end
  end
end
