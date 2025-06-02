# frozen_string_literal: true

##
# A Resolver::Specification contains a subset of the information
# contained in a Gem::Specification.  Only the information necessary for
# dependency resolution in the resolver is included.

class Gem::Resolver::Specification
  ##
  # The dependencies of the gem for this specification

  attr_reader :dependencies

  ##
  # The name of the gem for this specification

  attr_reader :name

  ##
  # The platform this gem works on.

  attr_reader :platform

  ##
  # The set this specification came from.

  attr_reader :set

  ##
  # The source for this specification

  attr_reader :source

  ##
  # The Gem::Specification for this Resolver::Specification.
  #
  # Implementers, note that #install updates @spec, so be sure to cache the
  # Gem::Specification in @spec when overriding.

  attr_reader :spec

  ##
  # The version of the gem for this specification.

  attr_reader :version

  ##
  # The required_ruby_version constraint for this specification.

  attr_reader :required_ruby_version

  ##
  # The required_ruby_version constraint for this specification.

  attr_reader :required_rubygems_version

  ##
  # Sets default instance variables for the specification.

  def initialize
    @dependencies = nil
    @name         = nil
    @platform     = nil
    @set          = nil
    @source       = nil
    @version      = nil
    @required_ruby_version = Gem::Requirement.default
    @required_rubygems_version = Gem::Requirement.default
  end

  ##
  # Fetches development dependencies if the source does not provide them by
  # default (see APISpecification).

  def fetch_development_dependencies # :nodoc:
  end

  ##
  # The name and version of the specification.
  #
  # Unlike Gem::Specification#full_name, the platform is not included.

  def full_name
    "#{@name}-#{@version}"
  end

  ##
  # Installs this specification using the Gem::Installer +options+.  The
  # install method yields a Gem::Installer instance, which indicates the
  # gem will be installed, or +nil+, which indicates the gem is already
  # installed.
  #
  # After installation #spec is updated to point to the just-installed
  # specification.

  def install(options = {})
    require_relative "../installer"

    gem = download options

    installer = Gem::Installer.at gem, options

    yield installer if block_given?

    @spec = installer.install
  end

  def download(options)
    dir = options[:install_dir] || Gem.dir

    Gem.ensure_gem_subdirectories dir

    source.download spec, dir
  end

  ##
  # Returns true if this specification is installable on this platform.

  def installable_platform?
    Gem::Platform.match_spec? spec
  end

  def local? # :nodoc:
    false
  end
end
