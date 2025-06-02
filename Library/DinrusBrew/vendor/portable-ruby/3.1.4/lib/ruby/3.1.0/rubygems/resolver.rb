# frozen_string_literal: true
require_relative "dependency"
require_relative "exceptions"
require_relative "util/list"

##
# Given a set of Gem::Dependency objects as +needed+ and a way to query the
# set of available specs via +set+, calculates a set of ActivationRequest
# objects which indicate all the specs that should be activated to meet the
# all the requirements.

class Gem::Resolver
  require_relative "resolver/molinillo"

  ##
  # If the DEBUG_RESOLVER environment variable is set then debugging mode is
  # enabled for the resolver.  This will display information about the state
  # of the resolver while a set of dependencies is being resolved.

  DEBUG_RESOLVER = !ENV["DEBUG_RESOLVER"].nil?

  ##
  # Set to true if all development dependencies should be considered.

  attr_accessor :development

  ##
  # Set to true if immediate development dependencies should be considered.

  attr_accessor :development_shallow

  ##
  # When true, no dependencies are looked up for requested gems.

  attr_accessor :ignore_dependencies

  ##
  # List of dependencies that could not be found in the configured sources.

  attr_reader :missing

  attr_reader :stats

  ##
  # Hash of gems to skip resolution.  Keyed by gem name, with arrays of
  # gem specifications as values.

  attr_accessor :skip_gems

  ##
  # When a missing dependency, don't stop. Just go on and record what was
  # missing.

  attr_accessor :soft_missing

  ##
  # Combines +sets+ into a ComposedSet that allows specification lookup in a
  # uniform manner.  If one of the +sets+ is itself a ComposedSet its sets are
  # flattened into the result ComposedSet.

  def self.compose_sets(*sets)
    sets.compact!

    sets = sets.map do |set|
      case set
      when Gem::Resolver::BestSet then
        set
      when Gem::Resolver::ComposedSet then
        set.sets
      else
        set
      end
    end.flatten

    case sets.length
    when 0 then
      raise ArgumentError, "one set in the composition must be non-nil"
    when 1 then
      sets.first
    else
      Gem::Resolver::ComposedSet.new(*sets)
    end
  end

  ##
  # Creates a Resolver that queries only against the already installed gems
  # for the +needed+ dependencies.

  def self.for_current_gems(needed)
    new needed, Gem::Resolver::CurrentSet.new
  end

  ##
  # Create Resolver object which will resolve the tree starting
  # with +needed+ Dependency objects.
  #
  # +set+ is an object that provides where to look for specifications to
  # satisfy the Dependencies. This defaults to IndexSet, which will query
  # rubygems.org.

  def initialize(needed, set = nil)
    @set = set || Gem::Resolver::IndexSet.new
    @needed = needed

    @development         = false
    @development_shallow = false
    @ignore_dependencies = false
    @missing             = []
    @skip_gems           = {}
    @soft_missing        = false
    @stats               = Gem::Resolver::Stats.new
  end

  def explain(stage, *data) # :nodoc:
    return unless DEBUG_RESOLVER

    d = data.map {|x| x.pretty_inspect }.join(", ")
    $stderr.printf "%10s %s\n", stage.to_s.upcase, d
  end

  def explain_list(stage) # :nodoc:
    return unless DEBUG_RESOLVER

    data = yield
    $stderr.printf "%10s (%d entries)\n", stage.to_s.upcase, data.size
    unless data.empty?
      require "pp"
      PP.pp data, $stderr
    end
  end

  ##
  # Creates an ActivationRequest for the given +dep+ and the last +possible+
  # specification.
  #
  # Returns the Specification and the ActivationRequest

  def activation_request(dep, possible) # :nodoc:
    spec = possible.pop

    explain :activate, [spec.full_name, possible.size]
    explain :possible, possible

    activation_request =
      Gem::Resolver::ActivationRequest.new spec, dep, possible

    return spec, activation_request
  end

  def requests(s, act, reqs=[]) # :nodoc:
    return reqs if @ignore_dependencies

    s.fetch_development_dependencies if @development

    s.dependencies.reverse_each do |d|
      next if d.type == :development && !@development
      next if d.type == :development && @development_shallow &&
              act.development?
      next if d.type == :development && @development_shallow &&
              act.parent

      reqs << Gem::Resolver::DependencyRequest.new(d, act)
      @stats.requirement!
    end

    @set.prefetch reqs

    @stats.record_requirements reqs

    reqs
  end

  include Molinillo::UI

  def output
    @output ||= debug? ? $stdout : File.open(IO::NULL, "w")
  end

  def debug?
    DEBUG_RESOLVER
  end

  include Molinillo::SpecificationProvider

  ##
  # Proceed with resolution! Returns an array of ActivationRequest objects.

  def resolve
    locking_dg = Molinillo::DependencyGraph.new
    Molinillo::Resolver.new(self, self).resolve(@needed.map {|d| DependencyRequest.new d, nil }, locking_dg).tsort.map(&:payload).compact
  rescue Molinillo::VersionConflict => e
    conflict = e.conflicts.values.first
    raise Gem::DependencyResolutionError, Conflict.new(conflict.requirement_trees.first.first, conflict.existing, conflict.requirement)
  ensure
    @output.close if defined?(@output) && !debug?
  end

  ##
  # Extracts the specifications that may be able to fulfill +dependency+ and
  # returns those that match the local platform and all those that match.

  def find_possible(dependency) # :nodoc:
    all = @set.find_all dependency

    if (skip_dep_gems = skip_gems[dependency.name]) && !skip_dep_gems.empty?
      matching = all.select do |api_spec|
        skip_dep_gems.any? {|s| api_spec.version == s.version }
      end

      all = matching unless matching.empty?
    end

    matching_platform = select_local_platforms all

    return matching_platform, all
  end

  ##
  # Returns the gems in +specs+ that match the local platform.

  def select_local_platforms(specs) # :nodoc:
    specs.select do |spec|
      Gem::Platform.installable? spec
    end
  end

  def search_for(dependency)
    possibles, all = find_possible(dependency)
    if !@soft_missing && possibles.empty?
      @missing << dependency
      exc = Gem::UnsatisfiableDependencyError.new dependency, all
      exc.errors = @set.errors
      raise exc
    end

    groups = Hash.new {|hash, key| hash[key] = [] }

    # create groups & sources in the same loop
    sources = possibles.map do |spec|
      source = spec.source
      groups[source] << spec
      source
    end.uniq.reverse

    activation_requests = []

    sources.each do |source|
      groups[source].
        sort_by {|spec| [spec.version, spec.platform =~ Gem::Platform.local ? 1 : 0] }.
        map {|spec| ActivationRequest.new spec, dependency }.
        each {|activation_request| activation_requests << activation_request }
    end

    activation_requests
  end

  def dependencies_for(specification)
    return [] if @ignore_dependencies
    spec = specification.spec
    requests(spec, specification)
  end

  def requirement_satisfied_by?(requirement, activated, spec)
    matches_spec = requirement.matches_spec? spec
    return matches_spec if @soft_missing

    matches_spec &&
      spec.spec.required_ruby_version.satisfied_by?(Gem.ruby_version) &&
      spec.spec.required_rubygems_version.satisfied_by?(Gem.rubygems_version)
  end

  def name_for(dependency)
    dependency.name
  end

  def allow_missing?(dependency)
    @missing << dependency
    @soft_missing
  end

  def sort_dependencies(dependencies, activated, conflicts)
    dependencies.sort_by.with_index do |dependency, i|
      name = name_for(dependency)
      [
        activated.vertex_named(name).payload ? 0 : 1,
        amount_constrained(dependency),
        conflicts[name] ? 0 : 1,
        activated.vertex_named(name).payload ? 0 : search_for(dependency).count,
        i, # for stable sort
      ]
    end
  end

  SINGLE_POSSIBILITY_CONSTRAINT_PENALTY = 1_000_000
  private_constant :SINGLE_POSSIBILITY_CONSTRAINT_PENALTY if defined?(private_constant)

  # returns an integer \in (-\infty, 0]
  # a number closer to 0 means the dependency is less constraining
  #
  # dependencies w/ 0 or 1 possibilities (ignoring version requirements)
  # are given very negative values, so they _always_ sort first,
  # before dependencies that are unconstrained
  def amount_constrained(dependency)
    @amount_constrained ||= {}
    @amount_constrained[dependency.name] ||= begin
      name_dependency = Gem::Dependency.new(dependency.name)
      dependency_request_for_name = Gem::Resolver::DependencyRequest.new(name_dependency, dependency.requester)
      all = @set.find_all(dependency_request_for_name).size

      if all <= 1
        all - SINGLE_POSSIBILITY_CONSTRAINT_PENALTY
      else
        search = search_for(dependency).size
        search - all
      end
    end
  end
  private :amount_constrained
end

require_relative "resolver/activation_request"
require_relative "resolver/conflict"
require_relative "resolver/dependency_request"
require_relative "resolver/requirement_list"
require_relative "resolver/stats"

require_relative "resolver/set"
require_relative "resolver/api_set"
require_relative "resolver/composed_set"
require_relative "resolver/best_set"
require_relative "resolver/current_set"
require_relative "resolver/git_set"
require_relative "resolver/index_set"
require_relative "resolver/installer_set"
require_relative "resolver/lock_set"
require_relative "resolver/vendor_set"
require_relative "resolver/source_set"

require_relative "resolver/specification"
require_relative "resolver/spec_specification"
require_relative "resolver/api_specification"
require_relative "resolver/git_specification"
require_relative "resolver/index_specification"
require_relative "resolver/installed_specification"
require_relative "resolver/local_specification"
require_relative "resolver/lock_specification"
require_relative "resolver/vendor_specification"
