# frozen_string_literal: true

module Gem
  class SpecificationRecord
    def self.dirs_from(paths)
      paths.map do |path|
        File.join(path, "specifications")
      end
    end

    def self.from_path(path)
      new(dirs_from([path]))
    end

    def initialize(dirs)
      @all = nil
      @stubs = nil
      @stubs_by_name = {}
      @spec_with_requirable_file = {}
      @active_stub_with_requirable_file = {}

      @dirs = dirs
    end

    # Sentinel object to represent "not found" stubs
    NOT_FOUND = Struct.new(:to_spec, :this).new
    private_constant :NOT_FOUND

    ##
    # Returns the list of all specifications in the record

    def all
      @all ||= stubs.map(&:to_spec)
    end

    ##
    # Returns a Gem::StubSpecification for every specification in the record

    def stubs
      @stubs ||= begin
        pattern = "*.gemspec"
        stubs = stubs_for_pattern(pattern, false)

        @stubs_by_name = stubs.select {|s| Gem::Platform.match_spec? s }.group_by(&:name)
        stubs
      end
    end

    ##
    # Returns a Gem::StubSpecification for every specification in the record
    # named +name+ only returns stubs that match Gem.platforms

    def stubs_for(name)
      if @stubs
        @stubs_by_name[name] || []
      else
        @stubs_by_name[name] ||= stubs_for_pattern("#{name}-*.gemspec").select do |s|
          s.name == name
        end
      end
    end

    ##
    # Finds stub specifications matching a pattern in the record, optionally
    # filtering out specs not matching the current platform

    def stubs_for_pattern(pattern, match_platform = true)
      installed_stubs = installed_stubs(pattern)
      installed_stubs.select! {|s| Gem::Platform.match_spec? s } if match_platform
      stubs = installed_stubs + Gem::Specification.default_stubs(pattern)
      Gem::Specification._resort!(stubs)
      stubs
    end

    ##
    # Adds +spec+ to the the record, keeping the collection properly sorted.

    def add_spec(spec)
      return if all.include? spec

      all << spec
      stubs << spec
      (@stubs_by_name[spec.name] ||= []) << spec

      Gem::Specification._resort!(@stubs_by_name[spec.name])
      Gem::Specification._resort!(stubs)
    end

    ##
    # Removes +spec+ from the record.

    def remove_spec(spec)
      all.delete spec.to_spec
      stubs.delete spec
      (@stubs_by_name[spec.name] || []).delete spec
    end

    ##
    # Sets the specs known by the record to +specs+.

    def all=(specs)
      @stubs_by_name = specs.group_by(&:name)
      @all = @stubs = specs
    end

    ##
    # Return full names of all specs in the record in sorted order.

    def all_names
      all.map(&:full_name)
    end

    include Enumerable

    ##
    # Enumerate every known spec.

    def each
      return enum_for(:each) unless block_given?

      all.each do |x|
        yield x
      end
    end

    ##
    # Returns every spec in the record that matches +name+ and optional +requirements+.

    def find_all_by_name(name, *requirements)
      req = Gem::Requirement.create(*requirements)
      env_req = Gem.env_requirement(name)

      matches = stubs_for(name).find_all do |spec|
        req.satisfied_by?(spec.version) && env_req.satisfied_by?(spec.version)
      end.map(&:to_spec)

      if name == "bundler" && !req.specific?
        require_relative "bundler_version_finder"
        Gem::BundlerVersionFinder.prioritize!(matches)
      end

      matches
    end

    ##
    # Return the best specification in the record that contains the file matching +path+.

    def find_by_path(path)
      path = path.dup.freeze
      spec = @spec_with_requirable_file[path] ||= stubs.find do |s|
        s.contains_requirable_file? path
      end || NOT_FOUND

      spec.to_spec
    end

    ##
    # Return the best specification in the record that contains the file
    # matching +path+ amongst the specs that are not activated.

    def find_inactive_by_path(path)
      stub = stubs.find do |s|
        next if s.activated?
        s.contains_requirable_file? path
      end
      stub&.to_spec
    end

    ##
    # Return the best specification in the record that contains the file
    # matching +path+, among those already activated.

    def find_active_stub_by_path(path)
      stub = @active_stub_with_requirable_file[path] ||= stubs.find do |s|
        s.activated? && s.contains_requirable_file?(path)
      end || NOT_FOUND

      stub.this
    end

    ##
    # Return the latest specs in the record, optionally including prerelease
    # specs if +prerelease+ is true.

    def latest_specs(prerelease)
      Gem::Specification._latest_specs stubs, prerelease
    end

    ##
    # Return the latest installed spec in the record for gem +name+.

    def latest_spec_for(name)
      latest_specs(true).find {|installed_spec| installed_spec.name == name }
    end

    private

    def installed_stubs(pattern)
      map_stubs(pattern) do |path, base_dir, gems_dir|
        Gem::StubSpecification.gemspec_stub(path, base_dir, gems_dir)
      end
    end

    def map_stubs(pattern)
      @dirs.flat_map do |dir|
        base_dir = File.dirname dir
        gems_dir = File.join base_dir, "gems"
        Gem::Specification.gemspec_stubs_in(dir, pattern) {|path| yield path, base_dir, gems_dir }
      end
    end
  end
end
