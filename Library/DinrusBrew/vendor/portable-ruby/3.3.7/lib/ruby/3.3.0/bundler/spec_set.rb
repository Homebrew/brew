# frozen_string_literal: true

require_relative "vendored_tsort"

module Bundler
  class SpecSet
    include Enumerable
    include TSort

    attr_reader :incomplete_specs

    def initialize(specs, incomplete_specs = [])
      @specs = specs
      @incomplete_specs = incomplete_specs
    end

    def for(dependencies, check = false, platforms = [nil])
      handled = ["bundler"].product(platforms).map {|k| [k, true] }.to_h
      deps = dependencies.product(platforms)
      specs = []

      loop do
        break unless dep = deps.shift

        name = dep[0].name
        platform = dep[1]
        incomplete = false

        key = [name, platform]
        next if handled.key?(key)

        handled[key] = true

        specs_for_dep = specs_for_dependency(*dep)
        if specs_for_dep.any?
          specs.concat(specs_for_dep)

          specs_for_dep.first.dependencies.each do |d|
            next if d.type == :development
            incomplete = true if d.name != "bundler" && lookup[d.name].nil?
            deps << [d, dep[1]]
          end
        else
          incomplete = true
        end

        if incomplete && check
          @incomplete_specs += lookup[name] || [LazySpecification.new(name, nil, nil)]
        end
      end

      specs.uniq
    end

    def add_extra_platforms!(platforms)
      return platforms.concat([Gem::Platform::RUBY]).uniq if @specs.empty?

      new_platforms = all_platforms.select do |platform|
        next if platforms.include?(platform)
        next unless GemHelpers.generic(platform) == Gem::Platform::RUBY

        complete_platform(platform)
      end
      return platforms if new_platforms.empty?

      platforms.concat(new_platforms)

      less_specific_platform = new_platforms.find {|platform| platform != Gem::Platform::RUBY && Bundler.local_platform === platform && platform === Bundler.local_platform }
      platforms.delete(Bundler.local_platform) if less_specific_platform

      platforms
    end

    def validate_deps(s)
      s.runtime_dependencies.each do |dep|
        next if dep.name == "bundler"

        return :missing unless names.include?(dep.name)
        return :invalid if none? {|spec| dep.matches_spec?(spec) }
      end

      :valid
    end

    def [](key)
      key = key.name if key.respond_to?(:name)
      lookup[key]&.reverse || []
    end

    def []=(key, value)
      @specs << value

      reset!
    end

    def delete(specs)
      Array(specs).each {|spec| @specs.delete(spec) }

      reset!
    end

    def sort!
      self
    end

    def to_a
      sorted.dup
    end

    def to_hash
      lookup.dup
    end

    def materialize(deps)
      materialized = self.for(deps, true)

      SpecSet.new(materialized, incomplete_specs)
    end

    # Materialize for all the specs in the spec set, regardless of what platform they're for
    # This is in contrast to how for does platform filtering (and specifically different from how `materialize` calls `for` only for the current platform)
    # @return [Array<Gem::Specification>]
    def materialized_for_all_platforms
      @specs.map do |s|
        next s unless s.is_a?(LazySpecification)
        s.source.remote!
        spec = s.materialize_for_installation
        raise GemNotFound, "Could not find #{s.full_name} in any of the sources" unless spec
        spec
      end
    end

    def incomplete_for_platform?(deps, platform)
      return false if @specs.empty?

      @incomplete_specs = []

      self.for(deps, true, [platform])

      @incomplete_specs.any?
    end

    def missing_specs
      @specs.select {|s| s.is_a?(LazySpecification) }
    end

    def -(other)
      SpecSet.new(to_a - other.to_a)
    end

    def find_by_name_and_platform(name, platform)
      @specs.detect {|spec| spec.name == name && spec.match_platform(platform) }
    end

    def specs_compatible_with(other)
      select do |spec|
        other.valid?(spec)
      end
    end

    def delete_by_name(name)
      @specs.reject! {|spec| spec.name == name }

      reset!
    end

    def what_required(spec)
      unless req = find {|s| s.runtime_dependencies.any? {|d| d.name == spec.name } }
        return [spec]
      end
      what_required(req) << spec
    end

    def <<(spec)
      @specs << spec
    end

    def length
      @specs.length
    end

    def size
      @specs.size
    end

    def empty?
      @specs.empty?
    end

    def each(&b)
      sorted.each(&b)
    end

    def names
      lookup.keys
    end

    def valid?(s)
      s.matches_current_metadata? && valid_dependencies?(s)
    end

    private

    def reset!
      @sorted = nil
      @lookup = nil
    end

    def complete_platform(platform)
      new_specs = []

      valid_platform = lookup.all? do |_, specs|
        spec = specs.first
        matching_specs = spec.source.specs.search([spec.name, spec.version])
        platform_spec = GemHelpers.select_best_platform_match(matching_specs, platform).find do |s|
          valid?(s)
        end

        if platform_spec
          new_specs << LazySpecification.from_spec(platform_spec) unless specs.include?(platform_spec)
          true
        else
          false
        end
      end

      if valid_platform && new_specs.any?
        @specs.concat(new_specs)

        reset!
      end

      valid_platform
    end

    def all_platforms
      @specs.flat_map {|spec| spec.source.specs.search([spec.name, spec.version]).map(&:platform) }.uniq
    end

    def valid_dependencies?(s)
      validate_deps(s) == :valid
    end

    def sorted
      rake = @specs.find {|s| s.name == "rake" }
      begin
        @sorted ||= ([rake] + tsort).compact.uniq
      rescue TSort::Cyclic => error
        cgems = extract_circular_gems(error)
        raise CyclicDependencyError, "Your bundle requires gems that depend" \
          " on each other, creating an infinite loop. Please remove either" \
          " gem '#{cgems[0]}' or gem '#{cgems[1]}' and try again."
      end
    end

    def extract_circular_gems(error)
      error.message.scan(/@name="(.*?)"/).flatten
    end

    def lookup
      @lookup ||= begin
        lookup = {}
        @specs.each do |s|
          lookup[s.name] ||= []
          lookup[s.name] << s
        end
        lookup
      end
    end

    def tsort_each_node
      # MUST sort by name for backwards compatibility
      @specs.sort_by(&:name).each {|s| yield s }
    end

    def specs_for_dependency(dep, platform)
      specs_for_name = lookup[dep.name]
      return [] unless specs_for_name

      if platform
        GemHelpers.select_best_platform_match(specs_for_name, platform, force_ruby: dep.force_ruby_platform)
      else
        GemHelpers.select_best_local_platform_match(specs_for_name, force_ruby: dep.force_ruby_platform || dep.default_force_ruby_platform)
      end
    end

    def tsort_each_child(s)
      s.dependencies.sort_by(&:name).each do |d|
        next if d.type == :development

        specs_for_name = lookup[d.name]
        next unless specs_for_name

        specs_for_name.each {|s2| yield s2 }
      end
    end
  end
end
