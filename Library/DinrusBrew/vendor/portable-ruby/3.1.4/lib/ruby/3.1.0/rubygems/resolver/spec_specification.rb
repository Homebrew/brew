# frozen_string_literal: true
##
# The Resolver::SpecSpecification contains common functionality for
# Resolver specifications that are backed by a Gem::Specification.

class Gem::Resolver::SpecSpecification < Gem::Resolver::Specification
  ##
  # A SpecSpecification is created for a +set+ for a Gem::Specification in
  # +spec+.  The +source+ is either where the +spec+ came from, or should be
  # loaded from.

  def initialize(set, spec, source = nil)
    @set    = set
    @source = source
    @spec   = spec
  end

  ##
  # The dependencies of the gem for this specification

  def dependencies
    spec.dependencies
  end

  ##
  # The required_ruby_version constraint for this specification

  def required_ruby_version
    spec.required_ruby_version
  end

  ##
  # The required_rubygems_version constraint for this specification

  def required_rubygems_version
    spec.required_rubygems_version
  end

  ##
  # The name and version of the specification.
  #
  # Unlike Gem::Specification#full_name, the platform is not included.

  def full_name
    "#{spec.name}-#{spec.version}"
  end

  ##
  # The name of the gem for this specification

  def name
    spec.name
  end

  ##
  # The platform this gem works on.

  def platform
    spec.platform
  end

  ##
  # The version of the gem for this specification.

  def version
    spec.version
  end
end
