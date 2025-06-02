# frozen_string_literal: true

class Gem::AvailableSet
  include Enumerable

  Tuple = Struct.new(:spec, :source)

  attr_accessor :remote # :nodoc:

  def initialize
    @set = []
    @sorted = nil
    @remote = true
  end

  attr_reader :set

  def add(spec, source)
    @set << Tuple.new(spec, source)
    @sorted = nil
    self
  end

  def <<(o)
    case o
    when Gem::AvailableSet
      s = o.set
    when Array
      s = o.map do |sp,so|
        if !sp.is_a?(Gem::Specification) || !so.is_a?(Gem::Source)
          raise TypeError, "Array must be in [[spec, source], ...] form"
        end

        Tuple.new(sp,so)
      end
    else
      raise TypeError, "must be a Gem::AvailableSet"
    end

    @set += s
    @sorted = nil

    self
  end

  ##
  # Yields each Tuple in this AvailableSet

  def each
    return enum_for __method__ unless block_given?

    @set.each do |tuple|
      yield tuple
    end
  end

  ##
  # Yields the Gem::Specification for each Tuple in this AvailableSet

  def each_spec
    return enum_for __method__ unless block_given?

    each do |tuple|
      yield tuple.spec
    end
  end

  def empty?
    @set.empty?
  end

  def all_specs
    @set.map(&:spec)
  end

  def match_platform!
    @set.reject! {|t| !Gem::Platform.match_spec?(t.spec) }
    @sorted = nil
    self
  end

  def sorted
    @sorted ||= @set.sort do |a,b|
      i = b.spec <=> a.spec
      i != 0 ? i : (a.source <=> b.source)
    end
  end

  def size
    @set.size
  end

  def source_for(spec)
    f = @set.find {|t| t.spec == spec }
    f.source
  end

  ##
  # Converts this AvailableSet into a RequestSet that can be used to install
  # gems.
  #
  # If +development+ is :none then no development dependencies are installed.
  # Other options are :shallow for only direct development dependencies of the
  # gems in this set or :all for all development dependencies.

  def to_request_set(development = :none)
    request_set = Gem::RequestSet.new
    request_set.development = development == :all

    each_spec do |spec|
      request_set.always_install << spec

      request_set.gem spec.name, spec.version
      request_set.import spec.development_dependencies if
        development == :shallow
    end

    request_set
  end

  ##
  #
  # Used by the Resolver, the protocol to use a AvailableSet as a
  # search Set.

  def find_all(req)
    dep = req.dependency

    match = @set.find_all do |t|
      dep.match? t.spec
    end

    match.map do |t|
      Gem::Resolver::LocalSpecification.new(self, t.spec, t.source)
    end
  end

  def prefetch(reqs)
  end

  def pick_best!
    return self if empty?

    @set = [sorted.first]
    @sorted = nil
    self
  end

  def remove_installed!(dep)
    @set.reject! do |_t|
      # already locally installed
      Gem::Specification.any? do |installed_spec|
        dep.name == installed_spec.name &&
          dep.requirement.satisfied_by?(installed_spec.version)
      end
    end

    @sorted = nil
    self
  end

  def inject_into_list(dep_list)
    @set.each {|t| dep_list.add t.spec }
  end
end
