# frozen_string_literal: true

require_relative "force_platform"

module Bundler
  class LazySpecification
    include MatchMetadata
    include MatchPlatform
    include ForcePlatform

    attr_reader :name, :version, :platform
    attr_accessor :source, :remote, :force_ruby_platform, :dependencies, :required_ruby_version, :required_rubygems_version

    alias_method :runtime_dependencies, :dependencies

    def self.from_spec(s)
      lazy_spec = new(s.name, s.version, s.platform, s.source)
      lazy_spec.dependencies = s.dependencies
      lazy_spec.required_ruby_version = s.required_ruby_version
      lazy_spec.required_rubygems_version = s.required_rubygems_version
      lazy_spec
    end

    def initialize(name, version, platform, source = nil)
      @name          = name
      @version       = version
      @dependencies  = []
      @required_ruby_version = Gem::Requirement.default
      @required_rubygems_version = Gem::Requirement.default
      @platform      = platform || Gem::Platform::RUBY
      @source        = source
      @force_ruby_platform = default_force_ruby_platform
    end

    def full_name
      @full_name ||= if platform == Gem::Platform::RUBY
        "#{@name}-#{@version}"
      else
        "#{@name}-#{@version}-#{platform}"
      end
    end

    def lock_name
      @lock_name ||= name_tuple.lock_name
    end

    def name_tuple
      Gem::NameTuple.new(@name, @version, @platform)
    end

    def ==(other)
      full_name == other.full_name
    end

    def eql?(other)
      full_name.eql?(other.full_name)
    end

    def hash
      full_name.hash
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
      out << "    #{lock_name}\n"

      dependencies.sort_by(&:to_s).uniq.each do |dep|
        next if dep.type == :development
        out << "    #{dep.to_lock}\n"
      end

      out
    end

    def materialize_for_installation
      source.local!

      matching_specs = source.specs.search(use_exact_resolved_specifications? ? self : [name, version])
      return self if matching_specs.empty?

      candidates = if use_exact_resolved_specifications?
        matching_specs
      else
        target_platform = ruby_platform_materializes_to_ruby_platform? ? platform : local_platform

        installable_candidates = GemHelpers.select_best_platform_match(matching_specs, target_platform)

        specification = __materialize__(installable_candidates, fallback_to_non_installable: false)
        return specification unless specification.nil?

        if target_platform != platform
          installable_candidates = GemHelpers.select_best_platform_match(matching_specs, platform)
        end

        installable_candidates
      end

      __materialize__(candidates)
    end

    # If in frozen mode, we fallback to a non-installable candidate because by
    # doing this we avoid re-resolving and potentially end up changing the
    # lock file, which is not allowed. In that case, we will give a proper error
    # about the mismatch higher up the stack, right before trying to install the
    # bad gem.
    def __materialize__(candidates, fallback_to_non_installable: Bundler.frozen_bundle?)
      search = candidates.reverse.find do |spec|
        spec.is_a?(StubSpecification) || spec.matches_current_metadata?
      end
      if search.nil? && fallback_to_non_installable
        search = candidates.last
      else
        search.dependencies = dependencies if search && search.full_name == full_name && (search.is_a?(RemoteSpecification) || search.is_a?(EndpointSpecification))
      end
      search
    end

    def to_s
      lock_name
    end

    def git_version
      return unless source.is_a?(Bundler::Source::Git)
      " #{source.revision[0..6]}"
    end

    def force_ruby_platform!
      @force_ruby_platform = true
    end

    private

    def use_exact_resolved_specifications?
      @use_exact_resolved_specifications ||= !source.is_a?(Source::Path) && ruby_platform_materializes_to_ruby_platform?
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
