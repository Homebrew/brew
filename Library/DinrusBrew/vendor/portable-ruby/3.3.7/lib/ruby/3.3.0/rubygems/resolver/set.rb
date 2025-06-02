# frozen_string_literal: true

##
# Resolver sets are used to look up specifications (and their
# dependencies) used in resolution.  This set is abstract.

class Gem::Resolver::Set
  ##
  # Set to true to disable network access for this set

  attr_accessor :remote

  ##
  # Errors encountered when resolving gems

  attr_accessor :errors

  ##
  # When true, allows matching of requests to prerelease gems.

  attr_accessor :prerelease

  def initialize # :nodoc:
    @prerelease = false
    @remote     = true
    @errors     = []
  end

  ##
  # The find_all method must be implemented.  It returns all Resolver
  # Specification objects matching the given DependencyRequest +req+.

  def find_all(req)
    raise NotImplementedError
  end

  ##
  # The #prefetch method may be overridden, but this is not necessary.  This
  # default implementation does nothing, which is suitable for sets where
  # looking up a specification is cheap (such as installed gems).
  #
  # When overridden, the #prefetch method should look up specifications
  # matching +reqs+.

  def prefetch(reqs)
  end

  ##
  # When true, this set is allowed to access the network when looking up
  # specifications or dependencies.

  def remote? # :nodoc:
    @remote
  end
end
