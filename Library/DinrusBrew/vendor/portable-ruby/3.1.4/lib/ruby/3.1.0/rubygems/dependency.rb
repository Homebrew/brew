# frozen_string_literal: true
##
# The Dependency class holds a Gem name and a Gem::Requirement.

class Gem::Dependency
  ##
  # Valid dependency types.
  #--
  # When this list is updated, be sure to change
  # Gem::Specification::CURRENT_SPECIFICATION_VERSION as well.
  #
  # REFACTOR: This type of constant, TYPES, indicates we might want
  # two classes, used via inheritance or duck typing.

  TYPES = [
    :development,
    :runtime,
  ].freeze

  ##
  # Dependency name or regular expression.

  attr_accessor :name

  ##
  # Allows you to force this dependency to be a prerelease.

  attr_writer :prerelease

  ##
  # Constructs a dependency with +name+ and +requirements+. The last
  # argument can optionally be the dependency type, which defaults to
  # <tt>:runtime</tt>.

  def initialize(name, *requirements)
    case name
    when String then # ok
    when Regexp then
      msg = ["NOTE: Dependency.new w/ a regexp is deprecated.",
             "Dependency.new called from #{Gem.location_of_caller.join(":")}"]
      warn msg.join("\n") unless Gem::Deprecate.skip
    else
      raise ArgumentError,
            "dependency name must be a String, was #{name.inspect}"
    end

    type         = Symbol === requirements.last ? requirements.pop : :runtime
    requirements = requirements.first if 1 == requirements.length # unpack

    unless TYPES.include? type
      raise ArgumentError, "Valid types are #{TYPES.inspect}, " +
                           "not #{type.inspect}"
    end

    @name        = name
    @requirement = Gem::Requirement.create requirements
    @type        = type
    @prerelease  = false

    # This is for Marshal backwards compatibility. See the comments in
    # +requirement+ for the dirty details.

    @version_requirements = @requirement
  end

  ##
  # A dependency's hash is the XOR of the hashes of +name+, +type+,
  # and +requirement+.

  def hash # :nodoc:
    name.hash ^ type.hash ^ requirement.hash
  end

  def inspect # :nodoc:
    if prerelease?
      "<%s type=%p name=%p requirements=%p prerelease=ok>" %
        [self.class, self.type, self.name, requirement.to_s]
    else
      "<%s type=%p name=%p requirements=%p>" %
        [self.class, self.type, self.name, requirement.to_s]
    end
  end

  ##
  # Does this dependency require a prerelease?

  def prerelease?
    @prerelease || requirement.prerelease?
  end

  ##
  # Is this dependency simply asking for the latest version
  # of a gem?

  def latest_version?
    @requirement.none?
  end

  def pretty_print(q) # :nodoc:
    q.group 1, "Gem::Dependency.new(", ")" do
      q.pp name
      q.text ","
      q.breakable

      q.pp requirement

      q.text ","
      q.breakable

      q.pp type
    end
  end

  ##
  # What does this dependency require?

  def requirement
    return @requirement if defined?(@requirement) && @requirement

    # @version_requirements and @version_requirement are legacy ivar
    # names, and supported here because older gems need to keep
    # working and Dependency doesn't implement marshal_dump and
    # marshal_load. In a happier world, this would be an
    # attr_accessor. The horrifying instance_variable_get you see
    # below is also the legacy of some old restructurings.
    #
    # Note also that because of backwards compatibility (loading new
    # gems in an old RubyGems installation), we can't add explicit
    # marshaling to this class until we want to make a big
    # break. Maybe 2.0.
    #
    # Children, define explicit marshal and unmarshal behavior for
    # public classes. Marshal formats are part of your public API.

    # REFACTOR: See above

    if defined?(@version_requirement) && @version_requirement
      version = @version_requirement.instance_variable_get :@version
      @version_requirement = nil
      @version_requirements = Gem::Requirement.new version
    end

    @requirement = @version_requirements if defined?(@version_requirements)
  end

  def requirements_list
    requirement.as_list
  end

  def to_s # :nodoc:
    if type != :runtime
      "#{name} (#{requirement}, #{type})"
    else
      "#{name} (#{requirement})"
    end
  end

  ##
  # Dependency type.

  def type
    @type ||= :runtime
  end

  def runtime?
    @type == :runtime || !@type
  end

  def ==(other) # :nodoc:
    Gem::Dependency === other &&
      self.name        == other.name &&
      self.type        == other.type &&
      self.requirement == other.requirement
  end

  ##
  # Dependencies are ordered by name.

  def <=>(other)
    self.name <=> other.name
  end

  ##
  # Uses this dependency as a pattern to compare to +other+. This
  # dependency will match if the name matches the other's name, and
  # other has only an equal version requirement that satisfies this
  # dependency.

  def =~(other)
    unless Gem::Dependency === other
      return unless other.respond_to?(:name) && other.respond_to?(:version)
      other = Gem::Dependency.new other.name, other.version
    end

    return false unless name === other.name

    reqs = other.requirement.requirements

    return false unless reqs.length == 1
    return false unless reqs.first.first == "="

    version = reqs.first.last

    requirement.satisfied_by? version
  end

  alias === =~

  ##
  # :call-seq:
  #   dep.match? name          => true or false
  #   dep.match? name, version => true or false
  #   dep.match? spec          => true or false
  #
  # Does this dependency match the specification described by +name+ and
  # +version+ or match +spec+?
  #
  # NOTE:  Unlike #matches_spec? this method does not return true when the
  # version is a prerelease version unless this is a prerelease dependency.

  def match?(obj, version=nil, allow_prerelease=false)
    if !version
      name = obj.name
      version = obj.version
    else
      name = obj
    end

    return false unless self.name === name

    version = Gem::Version.new version

    return true if requirement.none? && !version.prerelease?
    return false if version.prerelease? &&
                    !allow_prerelease &&
                    !prerelease?

    requirement.satisfied_by? version
  end

  ##
  # Does this dependency match +spec+?
  #
  # NOTE:  This is not a convenience method.  Unlike #match? this method
  # returns true when +spec+ is a prerelease version even if this dependency
  # is not a prerelease dependency.

  def matches_spec?(spec)
    return false unless name === spec.name
    return true  if requirement.none?

    requirement.satisfied_by?(spec.version)
  end

  ##
  # Merges the requirements of +other+ into this dependency

  def merge(other)
    unless name == other.name
      raise ArgumentError,
            "#{self} and #{other} have different names"
    end

    default = Gem::Requirement.default
    self_req = self.requirement
    other_req = other.requirement

    return self.class.new name, self_req  if other_req == default
    return self.class.new name, other_req if self_req  == default

    self.class.new name, self_req.as_list.concat(other_req.as_list)
  end

  def matching_specs(platform_only = false)
    env_req = Gem.env_requirement(name)
    matches = Gem::Specification.stubs_for(name).find_all do |spec|
      requirement.satisfied_by?(spec.version) && env_req.satisfied_by?(spec.version)
    end.map(&:to_spec)

    Gem::BundlerVersionFinder.prioritize!(matches) if prioritizes_bundler?

    if platform_only
      matches.reject! do |spec|
        spec.nil? || !Gem::Platform.match_spec?(spec)
      end
    end

    matches
  end

  ##
  # True if the dependency will not always match the latest version.

  def specific?
    @requirement.specific?
  end

  def prioritizes_bundler?
    name == "bundler".freeze && !specific?
  end

  def to_specs
    matches = matching_specs true

    # TODO: check Gem.activated_spec[self.name] in case matches falls outside

    if matches.empty?
      specs = Gem::Specification.stubs_for name

      if specs.empty?
        raise Gem::MissingSpecError.new name, requirement
      else
        raise Gem::MissingSpecVersionError.new name, requirement, specs
      end
    end

    # TODO: any other resolver validations should go here

    matches
  end

  def to_spec
    matches = self.to_specs.compact

    active = matches.find {|spec| spec.activated? }
    return active if active

    unless prerelease?
      # Move prereleases to the end of the list for >= 0 requirements
      pre, matches = matches.partition {|spec| spec.version.prerelease? }
      matches += pre if requirement == Gem::Requirement.default
    end

    matches.first
  end

  def identity
    if prerelease?
      if specific?
        :complete
      else
        :abs_latest
      end
    elsif latest_version?
      :latest
    else
      :released
    end
  end
end
