# frozen_string_literal: true

module Bundler
  class LockfileParser
    attr_reader :sources, :dependencies, :specs, :platforms, :bundler_version, :ruby_version

    BUNDLED      = "BUNDLED WITH".freeze
    DEPENDENCIES = "DEPENDENCIES".freeze
    PLATFORMS    = "PLATFORMS".freeze
    RUBY         = "RUBY VERSION".freeze
    GIT          = "GIT".freeze
    GEM          = "GEM".freeze
    PATH         = "PATH".freeze
    PLUGIN       = "PLUGIN SOURCE".freeze
    SPECS        = "  specs:".freeze
    OPTIONS      = /^  ([a-z]+): (.*)$/i.freeze
    SOURCE       = [GIT, GEM, PATH, PLUGIN].freeze

    SECTIONS_BY_VERSION_INTRODUCED = {
      Gem::Version.create("1.0") => [DEPENDENCIES, PLATFORMS, GIT, GEM, PATH].freeze,
      Gem::Version.create("1.10") => [BUNDLED].freeze,
      Gem::Version.create("1.12") => [RUBY].freeze,
      Gem::Version.create("1.13") => [PLUGIN].freeze,
    }.freeze

    KNOWN_SECTIONS = SECTIONS_BY_VERSION_INTRODUCED.values.flatten.freeze

    ENVIRONMENT_VERSION_SECTIONS = [BUNDLED, RUBY].freeze

    def self.sections_in_lockfile(lockfile_contents)
      lockfile_contents.scan(/^\w[\w ]*$/).uniq
    end

    def self.unknown_sections_in_lockfile(lockfile_contents)
      sections_in_lockfile(lockfile_contents) - KNOWN_SECTIONS
    end

    def self.sections_to_ignore(base_version = nil)
      base_version &&= base_version.release
      base_version ||= Gem::Version.create("1.0".dup)
      attributes = []
      SECTIONS_BY_VERSION_INTRODUCED.each do |version, introduced|
        next if version <= base_version
        attributes += introduced
      end
      attributes
    end

    def self.bundled_with
      lockfile = Bundler.default_lockfile
      return unless lockfile.file?

      lockfile_contents = Bundler.read_file(lockfile)
      return unless lockfile_contents.include?(BUNDLED)

      lockfile_contents.split(BUNDLED).last.strip
    end

    def initialize(lockfile)
      @platforms    = []
      @sources      = []
      @dependencies = {}
      @state        = nil
      @specs        = {}

      if lockfile.match(/<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|/)
        raise LockfileError, "Your #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)} contains merge conflicts.\n" \
          "Run `git checkout HEAD -- #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)}` first to get a clean lock."
      end

      lockfile.split(/(?:\r?\n)+/).each do |line|
        if SOURCE.include?(line)
          @state = :source
          parse_source(line)
        elsif line == DEPENDENCIES
          @state = :dependency
        elsif line == PLATFORMS
          @state = :platform
        elsif line == RUBY
          @state = :ruby
        elsif line == BUNDLED
          @state = :bundled_with
        elsif line =~ /^[^\s]/
          @state = nil
        elsif @state
          send("parse_#{@state}", line)
        end
      end
      @specs = @specs.values.sort_by(&:identifier)
    rescue ArgumentError => e
      Bundler.ui.debug(e)
      raise LockfileError, "Your lockfile is unreadable. Run `rm #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)}` " \
        "and then `bundle install` to generate a new lockfile."
    end

    def may_include_redundant_platform_specific_gems?
      bundler_version.nil? || bundler_version < Gem::Version.new("1.16.2")
    end

    private

    TYPES = {
      GIT    => Bundler::Source::Git,
      GEM    => Bundler::Source::Rubygems,
      PATH   => Bundler::Source::Path,
      PLUGIN => Bundler::Plugin,
    }.freeze

    def parse_source(line)
      case line
      when SPECS
        case @type
        when PATH
          @current_source = TYPES[@type].from_lock(@opts)
          @sources << @current_source
        when GIT
          @current_source = TYPES[@type].from_lock(@opts)
          @sources << @current_source
        when GEM
          @opts["remotes"] = Array(@opts.delete("remote")).reverse
          @current_source = TYPES[@type].from_lock(@opts)
          @sources << @current_source
        when PLUGIN
          @current_source = Plugin.source_from_lock(@opts)
          @sources << @current_source
        end
      when OPTIONS
        value = $2
        value = true if value == "true"
        value = false if value == "false"

        key = $1

        if @opts[key]
          @opts[key] = Array(@opts[key])
          @opts[key] << value
        else
          @opts[key] = value
        end
      when *SOURCE
        @current_source = nil
        @opts = {}
        @type = line
      else
        parse_spec(line)
      end
    end

    space = / /
    NAME_VERSION = /
      ^(#{space}{2}|#{space}{4}|#{space}{6})(?!#{space}) # Exactly 2, 4, or 6 spaces at the start of the line
      (.*?)                                              # Name
      (?:#{space}\(([^-]*)                               # Space, followed by version
      (?:-(.*))?\))?                                     # Optional platform
      (!)?                                               # Optional pinned marker
      $                                                  # Line end
    /xo.freeze

    def parse_dependency(line)
      return unless line =~ NAME_VERSION
      spaces = $1
      return unless spaces.size == 2
      name = $2
      version = $3
      pinned = $5

      version = version.split(",").map(&:strip) if version

      dep = Bundler::Dependency.new(name, version)

      if pinned && dep.name != "bundler"
        spec = @specs.find {|_, v| v.name == dep.name }
        dep.source = spec.last.source if spec

        # Path sources need to know what the default name / version
        # to use in the case that there are no gemspecs present. A fake
        # gemspec is created based on the version set on the dependency
        # TODO: Use the version from the spec instead of from the dependency
        if version && version.size == 1 && version.first =~ /^\s*= (.+)\s*$/ && dep.source.is_a?(Bundler::Source::Path)
          dep.source.name    = name
          dep.source.version = $1
        end
      end

      @dependencies[dep.name] = dep
    end

    def parse_spec(line)
      return unless line =~ NAME_VERSION
      spaces = $1
      name = $2
      version = $3
      platform = $4

      if spaces.size == 4
        version = Gem::Version.new(version)
        platform = platform ? Gem::Platform.new(platform) : Gem::Platform::RUBY
        @current_spec = LazySpecification.new(name, version, platform)
        @current_spec.source = @current_source
        @current_source.add_dependency_names(name)

        @specs[@current_spec.identifier] = @current_spec
      elsif spaces.size == 6
        version = version.split(",").map(&:strip) if version
        dep = Gem::Dependency.new(name, version)
        @current_spec.dependencies << dep
      end
    end

    def parse_platform(line)
      @platforms << Gem::Platform.new($1) if line =~ /^  (.*)$/
    end

    def parse_bundled_with(line)
      line = line.strip
      return unless Gem::Version.correct?(line)
      @bundler_version = Gem::Version.create(line)
    end

    def parse_ruby(line)
      @ruby_version = line.strip
    end
  end
end
