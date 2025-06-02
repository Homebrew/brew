# frozen_string_literal: true
##
# Represents a possible Specification object returned from IndexSet.  Used to
# delay needed to download full Specification objects when only the +name+
# and +version+ are needed.

class Gem::Resolver::IndexSpecification < Gem::Resolver::Specification
  ##
  # An IndexSpecification is created from the index format described in `gem
  # help generate_index`.
  #
  # The +set+ contains other specifications for this (URL) +source+.
  #
  # The +name+, +version+ and +platform+ are the name, version and platform of
  # the gem.

  def initialize(set, name, version, source, platform)
    super()

    @set = set
    @name = name
    @version = version
    @source = source
    @platform = Gem::Platform.new(platform.to_s)
    @original_platform = platform.to_s

    @spec = nil
  end

  ##
  # The dependencies of the gem for this specification

  def dependencies
    spec.dependencies
  end

  ##
  # The required_ruby_version constraint for this specification
  #
  # A fallback is included because when generated, some marshalled specs have it
  # set to +nil+.

  def required_ruby_version
    spec.required_ruby_version || Gem::Requirement.default
  end

  ##
  # The required_rubygems_version constraint for this specification
  #
  # A fallback is included because the original version of the specification
  # API didn't include that field, so some marshalled specs in the index have it
  # set to +nil+.

  def required_rubygems_version
    spec.required_rubygems_version || Gem::Requirement.default
  end

  def ==(other)
    self.class === other &&
      @name == other.name &&
      @version == other.version &&
      @platform == other.platform
  end

  def hash
    @name.hash ^ @version.hash ^ @platform.hash
  end

  def inspect # :nodoc:
    "#<%s %s source %s>" % [self.class, full_name, @source]
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[Index specification", "]" do
      q.breakable
      q.text full_name

      unless Gem::Platform::RUBY == @platform
        q.breakable
        q.text @platform.to_s
      end

      q.breakable
      q.text "source "
      q.pp @source
    end
  end

  ##
  # Fetches a Gem::Specification for this IndexSpecification from the #source.

  def spec # :nodoc:
    @spec ||=
      begin
        tuple = Gem::NameTuple.new @name, @version, @original_platform

        @source.fetch_spec tuple
      end
  end
end
