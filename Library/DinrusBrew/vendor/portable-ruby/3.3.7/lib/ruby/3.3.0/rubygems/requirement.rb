# frozen_string_literal: true

require_relative "version"

##
# A Requirement is a set of one or more version restrictions. It supports a
# few (<tt>=, !=, >, <, >=, <=, ~></tt>) different restriction operators.
#
# See Gem::Version for a description on how versions and requirements work
# together in RubyGems.

class Gem::Requirement
  OPS = { # :nodoc:
    "=" => lambda {|v, r| v == r },
    "!=" => lambda {|v, r| v != r },
    ">" => lambda {|v, r| v > r },
    "<" => lambda {|v, r| v < r },
    ">=" => lambda {|v, r| v >= r },
    "<=" => lambda {|v, r| v <= r },
    "~>" => lambda {|v, r| v >= r && v.release < r.bump },
  }.freeze

  SOURCE_SET_REQUIREMENT = Struct.new(:for_lockfile).new "!" # :nodoc:

  quoted = OPS.keys.map {|k| Regexp.quote k }.join "|"
  PATTERN_RAW = "\\s*(#{quoted})?\\s*(#{Gem::Version::VERSION_PATTERN})\\s*".freeze # :nodoc:

  ##
  # A regular expression that matches a requirement

  PATTERN = /\A#{PATTERN_RAW}\z/

  ##
  # The default requirement matches any non-prerelease version

  DefaultRequirement = [">=", Gem::Version.new(0)].freeze

  ##
  # The default requirement matches any version

  DefaultPrereleaseRequirement = [">=", Gem::Version.new("0.a")].freeze

  ##
  # Raised when a bad requirement is encountered

  class BadRequirementError < ArgumentError; end

  ##
  # Factory method to create a Gem::Requirement object.  Input may be
  # a Version, a String, or nil.  Intended to simplify client code.
  #
  # If the input is "weird", the default version requirement is
  # returned.

  def self.create(*inputs)
    return new inputs if inputs.length > 1

    input = inputs.shift

    case input
    when Gem::Requirement then
      input
    when Gem::Version, Array then
      new input
    when "!" then
      source_set
    else
      if input.respond_to? :to_str
        new [input.to_str]
      else
        default
      end
    end
  end

  def self.default
    new ">= 0"
  end

  def self.default_prerelease
    new ">= 0.a"
  end

  ###
  # A source set requirement, used for Gemfiles and lockfiles

  def self.source_set # :nodoc:
    SOURCE_SET_REQUIREMENT
  end

  ##
  # Parse +obj+, returning an <tt>[op, version]</tt> pair. +obj+ can
  # be a String or a Gem::Version.
  #
  # If +obj+ is a String, it can be either a full requirement
  # specification, like <tt>">= 1.2"</tt>, or a simple version number,
  # like <tt>"1.2"</tt>.
  #
  #     parse("> 1.0")                 # => [">", Gem::Version.new("1.0")]
  #     parse("1.0")                   # => ["=", Gem::Version.new("1.0")]
  #     parse(Gem::Version.new("1.0")) # => ["=,  Gem::Version.new("1.0")]

  def self.parse(obj)
    return ["=", obj] if Gem::Version === obj

    unless PATTERN =~ obj.to_s
      raise BadRequirementError, "Illformed requirement [#{obj.inspect}]"
    end

    if $1 == ">=" && $2 == "0"
      DefaultRequirement
    elsif $1 == ">=" && $2 == "0.a"
      DefaultPrereleaseRequirement
    else
      [-($1 || "="), Gem::Version.new($2)]
    end
  end

  ##
  # An array of requirement pairs. The first element of the pair is
  # the op, and the second is the Gem::Version.

  attr_reader :requirements # :nodoc:

  ##
  # Constructs a requirement from +requirements+. Requirements can be
  # Strings, Gem::Versions, or Arrays of those. +nil+ and duplicate
  # requirements are ignored. An empty set of +requirements+ is the
  # same as <tt>">= 0"</tt>.

  def initialize(*requirements)
    requirements = requirements.flatten
    requirements.compact!
    requirements.uniq!

    if requirements.empty?
      @requirements = [DefaultRequirement]
    else
      @requirements = requirements.map! {|r| self.class.parse r }
    end
  end

  ##
  # Concatenates the +new+ requirements onto this requirement.

  def concat(new)
    new = new.flatten
    new.compact!
    new.uniq!
    new = new.map {|r| self.class.parse r }

    @requirements.concat new
  end

  ##
  # Formats this requirement for use in a Gem::RequestSet::Lockfile.

  def for_lockfile # :nodoc:
    return if @requirements == [DefaultRequirement]

    list = requirements.sort_by do |_, version|
      version
    end.map do |op, version|
      "#{op} #{version}"
    end.uniq

    " (#{list.join ", "})"
  end

  ##
  # true if this gem has no requirements.

  def none?
    if @requirements.size == 1
      @requirements[0] == DefaultRequirement
    else
      false
    end
  end

  ##
  # true if the requirement is for only an exact version

  def exact?
    return false unless @requirements.size == 1
    @requirements[0][0] == "="
  end

  def as_list # :nodoc:
    requirements.map {|op, version| "#{op} #{version}" }
  end

  def hash # :nodoc:
    requirements.map {|r| r.first == "~>" ? [r[0], r[1].to_s] : r }.sort.hash
  end

  def marshal_dump # :nodoc:
    [@requirements]
  end

  def marshal_load(array) # :nodoc:
    @requirements = array[0]

    raise TypeError, "wrong @requirements" unless Array === @requirements
  end

  def yaml_initialize(tag, vals) # :nodoc:
    vals.each do |ivar, val|
      instance_variable_set "@#{ivar}", val
    end
  end

  def init_with(coder) # :nodoc:
    yaml_initialize coder.tag, coder.map
  end

  def to_yaml_properties # :nodoc:
    ["@requirements"]
  end

  def encode_with(coder) # :nodoc:
    coder.add "requirements", @requirements
  end

  ##
  # A requirement is a prerelease if any of the versions inside of it
  # are prereleases

  def prerelease?
    requirements.any? {|r| r.last.prerelease? }
  end

  def pretty_print(q) # :nodoc:
    q.group 1, "Gem::Requirement.new(", ")" do
      q.pp as_list
    end
  end

  ##
  # True if +version+ satisfies this Requirement.

  def satisfied_by?(version)
    raise ArgumentError, "Need a Gem::Version: #{version.inspect}" unless
      Gem::Version === version
    requirements.all? {|op, rv| OPS[op].call version, rv }
  end

  alias_method :===, :satisfied_by?
  alias_method :=~, :satisfied_by?

  ##
  # True if the requirement will not always match the latest version.

  def specific?
    return true if @requirements.length > 1 # GIGO, > 1, > 2 is silly

    !%w[> >=].include? @requirements.first.first # grab the operator
  end

  def to_s # :nodoc:
    as_list.join ", "
  end

  def ==(other) # :nodoc:
    return unless Gem::Requirement === other

    # An == check is always necessary
    return false unless _sorted_requirements == other._sorted_requirements

    # An == check is sufficient unless any requirements use ~>
    return true unless _tilde_requirements.any?

    # If any requirements use ~> we use the stricter `#eql?` that also checks
    # that version precision is the same
    _tilde_requirements.eql?(other._tilde_requirements)
  end

  protected

  def _sorted_requirements
    @_sorted_requirements ||= requirements.sort_by(&:to_s)
  end

  def _tilde_requirements
    @_tilde_requirements ||= _sorted_requirements.select {|r| r.first == "~>" }
  end

  def initialize_copy(other) # :nodoc:
    @requirements = other.requirements.dup
    super
  end
end

class Gem::Version
  # This is needed for compatibility with older yaml
  # gemspecs.

  Requirement = Gem::Requirement # :nodoc:
end
