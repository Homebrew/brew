# frozen_string_literal: true

module Bundler
  class Index
    include Enumerable

    def self.build
      i = new
      yield i
      i
    end

    attr_reader :specs, :all_specs, :sources
    protected :specs, :all_specs

    RUBY = "ruby".freeze
    NULL = "\0".freeze

    def initialize
      @sources = []
      @cache = {}
      @specs = Hash.new {|h, k| h[k] = {} }
      @all_specs = Hash.new {|h, k| h[k] = EMPTY_SEARCH }
    end

    def initialize_copy(o)
      @sources = o.sources.dup
      @cache = {}
      @specs = Hash.new {|h, k| h[k] = {} }
      @all_specs = Hash.new {|h, k| h[k] = EMPTY_SEARCH }

      o.specs.each do |name, hash|
        @specs[name] = hash.dup
      end
      o.all_specs.each do |name, array|
        @all_specs[name] = array.dup
      end
    end

    def inspect
      "#<#{self.class}:0x#{object_id} sources=#{sources.map(&:inspect)} specs.size=#{specs.size}>"
    end

    def empty?
      each { return false }
      true
    end

    def search_all(name)
      all_matches = local_search(name) + @all_specs[name]
      @sources.each do |source|
        all_matches.concat(source.search_all(name))
      end
      all_matches
    end

    # Search this index's specs, and any source indexes that this index knows
    # about, returning all of the results.
    def search(query)
      results = local_search(query)
      return results unless @sources.any?

      @sources.each do |source|
        results.concat(source.search(query))
      end
      results.uniq(&:full_name)
    end

    def local_search(query)
      case query
      when Gem::Specification, RemoteSpecification, LazySpecification, EndpointSpecification then search_by_spec(query)
      when String then specs_by_name(query)
      when Gem::Dependency then search_by_dependency(query)
      else
        raise "You can't search for a #{query.inspect}."
      end
    end

    alias_method :[], :search

    def <<(spec)
      @specs[spec.name][spec.full_name] = spec
      spec
    end

    def each(&blk)
      return enum_for(:each) unless blk
      specs.values.each do |spec_sets|
        spec_sets.values.each(&blk)
      end
      sources.each {|s| s.each(&blk) }
      self
    end

    def spec_names
      names = specs.keys + sources.map(&:spec_names)
      names.uniq!
      names
    end

    def unmet_dependency_names
      dependency_names.select do |name|
        search(name).empty?
      end
    end

    def dependency_names
      names = []
      each do |spec|
        spec.dependencies.each do |dep|
          next if dep.type == :development
          names << dep.name
        end
      end
      names.uniq
    end

    def use(other, override_dupes = false)
      return unless other
      other.each do |s|
        if (dupes = search_by_spec(s)) && !dupes.empty?
          # safe to << since it's a new array when it has contents
          @all_specs[s.name] = dupes << s
          next unless override_dupes
        end
        self << s
      end
      self
    end

    def size
      @sources.inject(@specs.size) do |size, source|
        size += source.size
      end
    end

    # Whether all the specs in self are in other
    # TODO: rename to #include?
    def ==(other)
      all? do |spec|
        other_spec = other[spec].first
        other_spec && dependencies_eql?(spec, other_spec) && spec.source == other_spec.source
      end
    end

    def dependencies_eql?(spec, other_spec)
      deps       = spec.dependencies.select {|d| d.type != :development }
      other_deps = other_spec.dependencies.select {|d| d.type != :development }
      deps.sort == other_deps.sort
    end

    def add_source(index)
      raise ArgumentError, "Source must be an index, not #{index.class}" unless index.is_a?(Index)
      @sources << index
      @sources.uniq! # need to use uniq! here instead of checking for the item before adding
    end

    private

    def specs_by_name(name)
      @specs[name].values
    end

    def search_by_dependency(dependency)
      @cache[dependency] ||= begin
        specs = specs_by_name(dependency.name)
        found = specs.select do |spec|
          next true if spec.source.is_a?(Source::Gemspec)
          dependency.matches_spec?(spec)
        end

        found
      end
    end

    EMPTY_SEARCH = [].freeze

    def search_by_spec(spec)
      spec = @specs[spec.name][spec.full_name]
      spec ? [spec] : EMPTY_SEARCH
    end
  end
end
