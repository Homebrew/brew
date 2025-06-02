# frozen_string_literal: true

module Bundler
  class LazySpecification
    include MatchPlatform

    attr_reader :name, :version, :dependencies, :platform
    attr_accessor :source, :remote, :force_ruby_platform

    def initialize(name, version, platform, source = nil)
      @name          = name
      @version       = version
      @dependencies  = []
      @platform      = platform || Gem::Platform::RUBY
      @source        = source
      @specification = nil
    end

    def full_name
      if platform == Gem::Platform::RUBY
        "#{@name}-#{@version}"
      else
        "#{@name}-#{@version}-#{platform}"
      end
    end

    def ==(other)
      identifier == other.identifier
    end

    def eql?(other)
      identifier.eql?(other.identifier)
    end

    def hash
      identifier.hash
    end

    ##
    # Does this locked specification satisfy +dependency+?
    #
    # NOTE: Rubygems default requirement is ">= 0", which doesn't match
    # prereleases of 0 versions, like "0.0.0.dev" or "0.0.0.SNAPSHOT". However,
    # bundler users expect those to work. We need to make sure that Gemfile
    # dependencies without explicit requirements (which use ">= 0" under the
    # hood by default) are still valid for locked specs using this kind of
    # versions. The method implements an ad-hoc fix for that. A better solution
    # might be to change default rubygems requirement of dependencies to be ">=
    # 0.A" but that's a major refactoring likely to break things. Hopefully we
    # can attempt it in the future.
    #

    def satisfies?(dependency)
      effective_requirement = dependency.requirement == Gem::Requirement.default ? Gem::Requirement.new(">= 0.A") : dependency.requirement

      @name == dependency.name && effective_requirement.satisfied_by?(Gem::Version.new(@version))
    end

    def to_lock
      out = String.new

      if platform == Gem::Platform::RUBY
        out << "    #{name} (#{version})\n"
      else
        out << "    #{name} (#{version}-#{platform})\n"
      end

      dependencies.sort_by(&:to_s).uniq.each do |dep|
        next if dep.type == :development
        out << "    #{dep.to_lock}\n"
      end

      out
    end

    def materialize_for_installation
      source.local!

      candidates = if source.is_a?(Source::Path) || !ruby_platform_materializes_to_ruby_platform?
        target_platform = ruby_platform_materializes_to_ruby_platform? ? platform : local_platform

        GemHelpers.select_best_platform_match(source.specs.search(Dependency.new(name, version)), target_platform)
      else
        source.specs.search(self)
      end

      return self if candidates.empty?

      __materialize__(candidates)
    end

    def __materialize__(candidates)
      @specification = begin
        search = candidates.reverse.find do |spec|
          spec.is_a?(StubSpecification) ||
            (spec.matches_current_ruby? &&
              spec.matches_current_rubygems?)
        end
        if search.nil? && Bundler.frozen_bundle?
          search = candidates.last
        else
          search.dependencies = dependencies if search && search.full_name == full_name && (search.is_a?(RemoteSpecification) || search.is_a?(EndpointSpecification))
        end
        search
      end
    end

    def respond_to?(*args)
      super || @specification ? @specification.respond_to?(*args) : nil
    end

    def to_s
      @__to_s ||= if platform == Gem::Platform::RUBY
        "#{name} (#{version})"
      else
        "#{name} (#{version}-#{platform})"
      end
    end

    def identifier
      @__identifier ||= [name, version, platform.to_s]
    end

    def git_version
      return unless source.is_a?(Bundler::Source::Git)
      " #{source.revision[0..6]}"
    end

    private

    def to_ary
      nil
    end

    def method_missing(method, *args, &blk)
      raise "LazySpecification has not been materialized yet (calling :#{method} #{args.inspect})" unless @specification

      return super unless respond_to?(method)

      @specification.send(method, *args, &blk)
    end

    #
    # For backwards compatibility with existing lockfiles, if the most specific
    # locked platform is not a specific platform like x86_64-linux or
    # universal-java-11, then we keep the previous behaviour of resolving the
    # best platform variant at materiliazation time. For previous bundler
    # versions (before 2.2.0) this was always the case (except when the lockfile
    # only included non-ruby platforms), but we're also keeping this behaviour
    # on newer bundlers unless users generate the lockfile from scratch or
    # explicitly add a more specific platform.
    #
    def ruby_platform_materializes_to_ruby_platform?
      generic_platform = generic_local_platform == Gem::Platform::JAVA ? Gem::Platform::JAVA : Gem::Platform::RUBY

      !Bundler.most_specific_locked_platform?(generic_platform) || force_ruby_platform || Bundler.settings[:force_ruby_platform]
    end
  end
end
