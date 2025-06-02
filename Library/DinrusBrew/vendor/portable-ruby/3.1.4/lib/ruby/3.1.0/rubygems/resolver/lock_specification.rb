# frozen_string_literal: true
##
# The LockSpecification comes from a lockfile (Gem::RequestSet::Lockfile).
#
# A LockSpecification's dependency information is pre-filled from the
# lockfile.

class Gem::Resolver::LockSpecification < Gem::Resolver::Specification
  attr_reader :sources

  def initialize(set, name, version, sources, platform)
    super()

    @name     = name
    @platform = platform
    @set      = set
    @source   = sources.first
    @sources  = sources
    @version  = version

    @dependencies = []
    @spec         = nil
  end

  ##
  # This is a null install as a locked specification is considered installed.
  # +options+ are ignored.

  def install(options = {})
    destination = options[:install_dir] || Gem.dir

    if File.exist? File.join(destination, "specifications", spec.spec_name)
      yield nil
      return
    end

    super
  end

  ##
  # Adds +dependency+ from the lockfile to this specification

  def add_dependency(dependency) # :nodoc:
    @dependencies << dependency
  end

  def pretty_print(q) # :nodoc:
    q.group 2, "[LockSpecification", "]" do
      q.breakable
      q.text "name: #{@name}"

      q.breakable
      q.text "version: #{@version}"

      unless @platform == Gem::Platform::RUBY
        q.breakable
        q.text "platform: #{@platform}"
      end

      unless @dependencies.empty?
        q.breakable
        q.text "dependencies:"
        q.breakable
        q.pp @dependencies
      end
    end
  end

  ##
  # A specification constructed from the lockfile is returned

  def spec
    @spec ||= Gem::Specification.find do |spec|
      spec.name == @name && spec.version == @version
    end

    @spec ||= Gem::Specification.new do |s|
      s.name     = @name
      s.version  = @version
      s.platform = @platform

      s.dependencies.concat @dependencies
    end
  end
end
