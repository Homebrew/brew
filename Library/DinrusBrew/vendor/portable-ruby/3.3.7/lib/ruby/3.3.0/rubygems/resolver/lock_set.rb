# frozen_string_literal: true

##
# A set of gems from a gem dependencies lockfile.

class Gem::Resolver::LockSet < Gem::Resolver::Set
  attr_reader :specs # :nodoc:

  ##
  # Creates a new LockSet from the given +sources+

  def initialize(sources)
    super()

    @sources = sources.map do |source|
      Gem::Source::Lock.new source
    end

    @specs = []
  end

  ##
  # Creates a new IndexSpecification in this set using the given +name+,
  # +version+ and +platform+.
  #
  # The specification's set will be the current set, and the source will be
  # the current set's source.

  def add(name, version, platform) # :nodoc:
    version = Gem::Version.new version
    specs = [
      Gem::Resolver::LockSpecification.new(self, name, version, @sources, platform),
    ]

    @specs.concat specs

    specs
  end

  ##
  # Returns an Array of IndexSpecification objects matching the
  # DependencyRequest +req+.

  def find_all(req)
    @specs.select do |spec|
      req.match? spec
    end
  end

  ##
  # Loads a Gem::Specification with the given +name+, +version+ and
  # +platform+.  +source+ is ignored.

  def load_spec(name, version, platform, source) # :nodoc:
    dep = Gem::Dependency.new name, version

    found = @specs.find do |spec|
      dep.matches_spec?(spec) && spec.platform == platform
    end

    tuple = Gem::NameTuple.new found.name, found.version, found.platform

    found.source.fetch_spec tuple
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[LockSet", "]" do
      q.breakable
      q.text "source:"

      q.breakable
      q.pp @source

      q.breakable
      q.text "specs:"

      q.breakable
      q.pp @specs.map(&:full_name)
    end
  end
end
