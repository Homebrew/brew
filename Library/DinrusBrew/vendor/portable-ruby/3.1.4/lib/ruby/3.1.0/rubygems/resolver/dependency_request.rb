# frozen_string_literal: true
##
# Used Internally. Wraps a Dependency object to also track which spec
# contained the Dependency.

class Gem::Resolver::DependencyRequest
  ##
  # The wrapped Gem::Dependency

  attr_reader :dependency

  ##
  # The request for this dependency.

  attr_reader :requester

  ##
  # Creates a new DependencyRequest for +dependency+ from +requester+.
  # +requester may be nil if the request came from a user.

  def initialize(dependency, requester)
    @dependency = dependency
    @requester  = requester
  end

  def ==(other) # :nodoc:
    case other
    when Gem::Dependency
      @dependency == other
    when Gem::Resolver::DependencyRequest
      @dependency == other.dependency
    else
      false
    end
  end

  ##
  # Is this dependency a development dependency?

  def development?
    @dependency.type == :development
  end

  ##
  # Does this dependency request match +spec+?
  #
  # NOTE:  #match? only matches prerelease versions when #dependency is a
  # prerelease dependency.

  def match?(spec, allow_prerelease = false)
    @dependency.match? spec, nil, allow_prerelease
  end

  ##
  # Does this dependency request match +spec+?
  #
  # NOTE:  #matches_spec? matches prerelease versions.  See also #match?

  def matches_spec?(spec)
    @dependency.matches_spec? spec
  end

  ##
  # The name of the gem this dependency request is requesting.

  def name
    @dependency.name
  end

  def type
    @dependency.type
  end

  ##
  # Indicate that the request is for a gem explicitly requested by the user

  def explicit?
    @requester.nil?
  end

  ##
  # Indicate that the request is for a gem requested as a dependency of
  # another gem

  def implicit?
    !explicit?
  end

  ##
  # Return a String indicating who caused this request to be added (only
  # valid for implicit requests)

  def request_context
    @requester ? @requester.request : "(unknown)"
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[Dependency request ", "]" do
      q.breakable
      q.text @dependency.to_s

      q.breakable
      q.text " requested by "
      q.pp @requester
    end
  end

  ##
  # The version requirement for this dependency request

  def requirement
    @dependency.requirement
  end

  def to_s # :nodoc:
    @dependency.to_s
  end
end
