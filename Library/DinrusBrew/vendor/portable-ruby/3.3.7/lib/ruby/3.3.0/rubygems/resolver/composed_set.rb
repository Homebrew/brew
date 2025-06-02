# frozen_string_literal: true

##
# A ComposedSet allows multiple sets to be queried like a single set.
#
# To create a composed set with any number of sets use:
#
#   Gem::Resolver.compose_sets set1, set2
#
# This method will eliminate nesting of composed sets.

class Gem::Resolver::ComposedSet < Gem::Resolver::Set
  attr_reader :sets # :nodoc:

  ##
  # Creates a new ComposedSet containing +sets+.  Use
  # Gem::Resolver::compose_sets instead.

  def initialize(*sets)
    super()

    @sets = sets
  end

  ##
  # When +allow_prerelease+ is set to +true+ prereleases gems are allowed to
  # match dependencies.

  def prerelease=(allow_prerelease)
    super

    sets.each do |set|
      set.prerelease = allow_prerelease
    end
  end

  ##
  # Sets the remote network access for all composed sets.

  def remote=(remote)
    super

    @sets.each {|set| set.remote = remote }
  end

  def errors
    @errors + @sets.map(&:errors).flatten
  end

  ##
  # Finds all specs matching +req+ in all sets.

  def find_all(req)
    @sets.map do |s|
      s.find_all req
    end.flatten
  end

  ##
  # Prefetches +reqs+ in all sets.

  def prefetch(reqs)
    @sets.each {|s| s.prefetch(reqs) }
  end
end
