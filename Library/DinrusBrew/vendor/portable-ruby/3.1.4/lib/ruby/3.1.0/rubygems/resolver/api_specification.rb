# frozen_string_literal: true
##
# Represents a specification retrieved via the rubygems.org API.
#
# This is used to avoid loading the full Specification object when all we need
# is the name, version, and dependencies.

class Gem::Resolver::APISpecification < Gem::Resolver::Specification
  ##
  # We assume that all instances of this class are immutable;
  # so avoid duplicated generation for performance.
  @@cache = {}
  def self.new(set, api_data)
    cache_key = [set, api_data]
    cache = @@cache[cache_key]
    return cache if cache
    @@cache[cache_key] = super
  end

  ##
  # Creates an APISpecification for the given +set+ from the rubygems.org
  # +api_data+.
  #
  # See https://guides.rubygems.org/rubygems-org-api/#misc_methods for the
  # format of the +api_data+.

  def initialize(set, api_data)
    super()

    @set = set
    @name = api_data[:name]
    @version = Gem::Version.new(api_data[:number]).freeze
    @platform = Gem::Platform.new(api_data[:platform]).freeze
    @original_platform = api_data[:platform].freeze
    @dependencies = api_data[:dependencies].map do |name, ver|
      Gem::Dependency.new(name, ver.split(/\s*,\s*/)).freeze
    end.freeze
    @required_ruby_version = Gem::Requirement.new(api_data.dig(:requirements, :ruby)).freeze
    @required_rubygems_version = Gem::Requirement.new(api_data.dig(:requirements, :rubygems)).freeze
  end

  def ==(other) # :nodoc:
    self.class === other &&
      @set          == other.set &&
      @name         == other.name &&
      @version      == other.version &&
      @platform     == other.platform
  end

  def hash
    @set.hash ^ @name.hash ^ @version.hash ^ @platform.hash
  end

  def fetch_development_dependencies # :nodoc:
    spec = source.fetch_spec Gem::NameTuple.new @name, @version, @platform

    @dependencies = spec.dependencies
  end

  def installable_platform? # :nodoc:
    Gem::Platform.match_gem? @platform, @name
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[APISpecification", "]" do
      q.breakable
      q.text "name: #{name}"

      q.breakable
      q.text "version: #{version}"

      q.breakable
      q.text "platform: #{platform}"

      q.breakable
      q.text "dependencies:"
      q.breakable
      q.pp @dependencies

      q.breakable
      q.text "set uri: #{@set.dep_uri}"
    end
  end

  ##
  # Fetches a Gem::Specification for this APISpecification.

  def spec # :nodoc:
    @spec ||=
      begin
        tuple = Gem::NameTuple.new @name, @version, @platform
        source.fetch_spec tuple
      rescue Gem::RemoteFetcher::FetchError
        raise if @original_platform == @platform

        tuple = Gem::NameTuple.new @name, @version, @original_platform
        source.fetch_spec tuple
      end
  end

  def source # :nodoc:
    @set.source
  end
end
