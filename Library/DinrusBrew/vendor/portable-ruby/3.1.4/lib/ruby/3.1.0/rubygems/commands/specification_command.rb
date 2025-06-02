# frozen_string_literal: true
require_relative "../command"
require_relative "../local_remote_options"
require_relative "../version_option"
require_relative "../package"

class Gem::Commands::SpecificationCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::VersionOption

  def initialize
    Gem.load_yaml

    super "specification", "Display gem specification (in yaml)",
          :domain => :local, :version => Gem::Requirement.default,
          :format => :yaml

    add_version_option("examine")
    add_platform_option
    add_prerelease_option

    add_option("--all", "Output specifications for all versions of",
               "the gem") do |value, options|
      options[:all] = true
    end

    add_option("--ruby", "Output ruby format") do |value, options|
      options[:format] = :ruby
    end

    add_option("--yaml", "Output YAML format") do |value, options|
      options[:format] = :yaml
    end

    add_option("--marshal", "Output Marshal format") do |value, options|
      options[:format] = :marshal
    end

    add_local_remote_options
  end

  def arguments # :nodoc:
    <<-ARGS
GEMFILE       name of gem to show the gemspec for
FIELD         name of gemspec field to show
    ARGS
  end

  def defaults_str # :nodoc:
    "--local --version '#{Gem::Requirement.default}' --yaml"
  end

  def description # :nodoc:
    <<-EOF
The specification command allows you to extract the specification from
a gem for examination.

The specification can be output in YAML, ruby or Marshal formats.

Specific fields in the specification can be extracted in YAML format:

  $ gem spec rake summary
  --- Ruby based make-like utility.
  ...

    EOF
  end

  def usage # :nodoc:
    "#{program_name} [GEMFILE] [FIELD]"
  end

  def execute
    specs = []
    gem = options[:args].shift

    unless gem
      raise Gem::CommandLineError,
            "Please specify a gem name or file on the command line"
    end

    case v = options[:version]
    when String
      req = Gem::Requirement.create v
    when Gem::Requirement
      req = v
    else
      raise Gem::CommandLineError, "Unsupported version type: '#{v}'"
    end

    if !req.none? && options[:all]
      alert_error "Specify --all or -v, not both"
      terminate_interaction 1
    end

    if options[:all]
      dep = Gem::Dependency.new gem
    else
      dep = Gem::Dependency.new gem, req
    end

    field = get_one_optional_argument

    raise Gem::CommandLineError, "--ruby and FIELD are mutually exclusive" if
      field && options[:format] == :ruby

    if local?
      if File.exist? gem
        specs << Gem::Package.new(gem).spec rescue nil
      end

      if specs.empty?
        specs.push(*dep.matching_specs)
      end
    end

    if remote?
      dep.prerelease = options[:prerelease]
      found, _ = Gem::SpecFetcher.fetcher.spec_for_dependency dep

      specs.push(*found.map {|spec,| spec })
    end

    if specs.empty?
      alert_error "No gem matching '#{dep}' found"
      terminate_interaction 1
    end

    platform = get_platform_from_requirements(options)

    if platform
      specs = specs.select {|s| s.platform.to_s == platform }
    end

    unless options[:all]
      specs = [specs.max_by {|s| s.version }]
    end

    specs.each do |s|
      s = s.send field if field

      say case options[:format]
      when :ruby then s.to_ruby
      when :marshal then Marshal.dump s
      else s.to_yaml
      end

      say "\n"
    end
  end
end
