# frozen_string_literal: true

##
# Specifies a Specification object that should be activated.  Also contains a
# dependency that was used to introduce this activation.

class Gem::Resolver::ActivationRequest
  ##
  # The parent request for this activation request.

  attr_reader :request

  ##
  # The specification to be activated.

  attr_reader :spec

  ##
  # Creates a new ActivationRequest that will activate +spec+.  The parent
  # +request+ is used to provide diagnostics in case of conflicts.

  def initialize(spec, request)
    @spec = spec
    @request = request
  end

  def ==(other) # :nodoc:
    case other
    when Gem::Specification
      @spec == other
    when Gem::Resolver::ActivationRequest
      @spec == other.spec
    else
      false
    end
  end

  def eql?(other)
    self == other
  end

  def hash
    @spec.hash
  end

  ##
  # Is this activation request for a development dependency?

  def development?
    @request.development?
  end

  ##
  # Downloads a gem at +path+ and returns the file path.

  def download(path)
    Gem.ensure_gem_subdirectories path

    if @spec.respond_to? :sources
      exception = nil
      path = @spec.sources.find do |source|
        source.download full_spec, path
      rescue exception
      end
      return path      if path
      raise  exception if exception

    elsif @spec.respond_to? :source
      source = @spec.source
      source.download full_spec, path

    else
      source = Gem.sources.first
      source.download full_spec, path
    end
  end

  ##
  # The full name of the specification to be activated.

  def full_name
    name_tuple.full_name
  end

  alias_method :to_s, :full_name

  ##
  # The Gem::Specification for this activation request.

  def full_spec
    Gem::Specification === @spec ? @spec : @spec.spec
  end

  def inspect # :nodoc:
    format("#<%s for %p from %s>", self.class, @spec, @request)
  end

  ##
  # True if the requested gem has already been installed.

  def installed?
    case @spec
    when Gem::Resolver::VendorSpecification then
      true
    else
      this_spec = full_spec

      Gem::Specification.any? do |s|
        s == this_spec && s.base_dir == this_spec.base_dir
      end
    end
  end

  ##
  # The name of this activation request's specification

  def name
    @spec.name
  end

  ##
  # Return the ActivationRequest that contained the dependency
  # that we were activated for.

  def parent
    @request.requester
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[Activation request", "]" do
      q.breakable
      q.pp @spec

      q.breakable
      q.text " for "
      q.pp @request
    end
  end

  ##
  # The version of this activation request's specification

  def version
    @spec.version
  end

  ##
  # The platform of this activation request's specification

  def platform
    @spec.platform
  end

  private

  def name_tuple
    @name_tuple ||= Gem::NameTuple.new(name, version, platform)
  end
end
