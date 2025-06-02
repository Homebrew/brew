# frozen_string_literal: true
require_relative "remote_fetcher"
require_relative "user_interaction"
require_relative "errors"
require_relative "text"
require_relative "name_tuple"

##
# SpecFetcher handles metadata updates from remote gem repositories.

class Gem::SpecFetcher
  include Gem::UserInteraction
  include Gem::Text

  ##
  # Cache of latest specs

  attr_reader :latest_specs # :nodoc:

  ##
  # Sources for this SpecFetcher

  attr_reader :sources # :nodoc:

  ##
  # Cache of all released specs

  attr_reader :specs # :nodoc:

  ##
  # Cache of prerelease specs

  attr_reader :prerelease_specs # :nodoc:

  @fetcher = nil

  ##
  # Default fetcher instance.  Use this instead of ::new to reduce object
  # allocation.

  def self.fetcher
    @fetcher ||= new
  end

  def self.fetcher=(fetcher) # :nodoc:
    @fetcher = fetcher
  end

  ##
  # Creates a new SpecFetcher.  Ordinarily you want to use the default fetcher
  # from Gem::SpecFetcher::fetcher which uses the Gem.sources.
  #
  # If you need to retrieve specifications from a different +source+, you can
  # send it as an argument.

  def initialize(sources = nil)
    @sources = sources || Gem.sources

    @update_cache =
      begin
        File.stat(Gem.user_home).uid == Process.uid
      rescue Errno::EACCES, Errno::ENOENT
        false
      end

    @specs = {}
    @latest_specs = {}
    @prerelease_specs = {}

    @caches = {
      :latest => @latest_specs,
      :prerelease => @prerelease_specs,
      :released => @specs,
    }

    @fetcher = Gem::RemoteFetcher.fetcher
  end

  ##
  #
  # Find and fetch gem name tuples that match +dependency+.
  #
  # If +matching_platform+ is false, gems for all platforms are returned.

  def search_for_dependency(dependency, matching_platform=true)
    found = {}

    rejected_specs = {}

    list, errors = available_specs(dependency.identity)

    list.each do |source, specs|
      if dependency.name.is_a?(String) && specs.respond_to?(:bsearch)
        start_index = (0 ... specs.length).bsearch {|i| specs[i].name >= dependency.name }
        end_index   = (0 ... specs.length).bsearch {|i| specs[i].name > dependency.name }
        specs = specs[start_index ... end_index] if start_index && end_index
      end

      found[source] = specs.select do |tup|
        if dependency.match?(tup)
          if matching_platform && !Gem::Platform.match_gem?(tup.platform, tup.name)
            pm = (
              rejected_specs[dependency] ||= \
                Gem::PlatformMismatch.new(tup.name, tup.version))
            pm.add_platform tup.platform
            false
          else
            true
          end
        end
      end
    end

    errors += rejected_specs.values

    tuples = []

    found.each do |source, specs|
      specs.each do |s|
        tuples << [s, source]
      end
    end

    tuples = tuples.sort_by {|x| x[0].version }

    return [tuples, errors]
  end

  ##
  # Return all gem name tuples who's names match +obj+

  def detect(type=:complete)
    tuples = []

    list, _ = available_specs(type)
    list.each do |source, specs|
      specs.each do |tup|
        if yield(tup)
          tuples << [tup, source]
        end
      end
    end

    tuples
  end

  ##
  # Find and fetch specs that match +dependency+.
  #
  # If +matching_platform+ is false, gems for all platforms are returned.

  def spec_for_dependency(dependency, matching_platform=true)
    tuples, errors = search_for_dependency(dependency, matching_platform)

    specs = []
    tuples.each do |tup, source|
      begin
        spec = source.fetch_spec(tup)
      rescue Gem::RemoteFetcher::FetchError => e
        errors << Gem::SourceFetchProblem.new(source, e)
      else
        specs << [spec, source]
      end
    end

    return [specs, errors]
  end

  ##
  # Suggests gems based on the supplied +gem_name+. Returns an array of
  # alternative gem names.

  def suggest_gems_from_name(gem_name, type = :latest, num_results = 5)
    gem_name        = gem_name.downcase.tr("_-", "")
    max             = gem_name.size / 2
    names           = available_specs(type).first.values.flatten(1)

    matches = names.map do |n|
      next unless n.match_platform?
      [n.name, 0] if n.name.downcase.tr("_-", "").include?(gem_name)
    end.compact

    if matches.length < num_results
      matches += names.map do |n|
        next unless n.match_platform?
        distance = levenshtein_distance gem_name, n.name.downcase.tr("_-", "")
        next if distance >= max
        return [n.name] if distance == 0
        [n.name, distance]
      end.compact
    end

    matches = if matches.empty? && type != :prerelease
      suggest_gems_from_name gem_name, :prerelease
    else
      matches.uniq.sort_by {|name, dist| dist }
    end

    matches.map {|name, dist| name }.uniq.first(num_results)
  end

  ##
  # Returns a list of gems available for each source in Gem::sources.
  #
  # +type+ can be one of 3 values:
  # :released   => Return the list of all released specs
  # :complete   => Return the list of all specs
  # :latest     => Return the list of only the highest version of each gem
  # :prerelease => Return the list of all prerelease only specs
  #

  def available_specs(type)
    errors = []
    list = {}

    @sources.each_source do |source|
      begin
        names = case type
        when :latest
          tuples_for source, :latest
        when :released
          tuples_for source, :released
        when :complete
          names =
            tuples_for(source, :prerelease, true) +
            tuples_for(source, :released)

          names.sort
        when :abs_latest
          names =
            tuples_for(source, :prerelease, true) +
            tuples_for(source, :latest)

          names.sort
        when :prerelease
          tuples_for(source, :prerelease)
        else
          raise Gem::Exception, "Unknown type - :#{type}"
        end
      rescue Gem::RemoteFetcher::FetchError => e
        errors << Gem::SourceFetchProblem.new(source, e)
      else
        list[source] = names
      end
    end

    [list, errors]
  end

  ##
  # Retrieves NameTuples from +source+ of the given +type+ (:prerelease,
  # etc.).  If +gracefully_ignore+ is true, errors are ignored.

  def tuples_for(source, type, gracefully_ignore=false) # :nodoc:
    @caches[type][source.uri] ||=
      source.load_specs(type).sort_by {|tup| tup.name }
  rescue Gem::RemoteFetcher::FetchError
    raise unless gracefully_ignore
    []
  end
end
