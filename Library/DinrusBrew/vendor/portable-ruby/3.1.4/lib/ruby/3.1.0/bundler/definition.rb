# frozen_string_literal: true

require_relative "lockfile_parser"

module Bundler
  class Definition
    include GemHelpers

    class << self
      # Do not create or modify a lockfile (Makes #lock a noop)
      attr_accessor :no_lock
    end

    attr_reader(
      :dependencies,
      :locked_deps,
      :locked_gems,
      :platforms,
      :requires,
      :ruby_version,
      :lockfile,
      :gemfiles
    )

    # Given a gemfile and lockfile creates a Bundler definition
    #
    # @param gemfile [Pathname] Path to Gemfile
    # @param lockfile [Pathname,nil] Path to Gemfile.lock
    # @param unlock [Hash, Boolean, nil] Gems that have been requested
    #   to be updated or true if all gems should be updated
    # @return [Bundler::Definition]
    def self.build(gemfile, lockfile, unlock)
      unlock ||= {}
      gemfile = Pathname.new(gemfile).expand_path

      raise GemfileNotFound, "#{gemfile} not found" unless gemfile.file?

      Dsl.evaluate(gemfile, lockfile, unlock)
    end

    #
    # How does the new system work?
    #
    # * Load information from Gemfile and Lockfile
    # * Invalidate stale locked specs
    #  * All specs from stale source are stale
    #  * All specs that are reachable only through a stale
    #    dependency are stale.
    # * If all fresh dependencies are satisfied by the locked
    #  specs, then we can try to resolve locally.
    #
    # @param lockfile [Pathname] Path to Gemfile.lock
    # @param dependencies [Array(Bundler::Dependency)] array of dependencies from Gemfile
    # @param sources [Bundler::SourceList]
    # @param unlock [Hash, Boolean, nil] Gems that have been requested
    #   to be updated or true if all gems should be updated
    # @param ruby_version [Bundler::RubyVersion, nil] Requested Ruby Version
    # @param optional_groups [Array(String)] A list of optional groups
    def initialize(lockfile, dependencies, sources, unlock, ruby_version = nil, optional_groups = [], gemfiles = [])
      if [true, false].include?(unlock)
        @unlocking_bundler = false
        @unlocking = unlock
      else
        @unlocking_bundler = unlock.delete(:bundler)
        @unlocking = unlock.any? {|_k, v| !Array(v).empty? }
      end

      @dependencies    = dependencies
      @sources         = sources
      @unlock          = unlock
      @optional_groups = optional_groups
      @remote          = false
      @prefer_local    = false
      @specs           = nil
      @ruby_version    = ruby_version
      @gemfiles        = gemfiles

      @lockfile               = lockfile
      @lockfile_contents      = String.new
      @locked_bundler_version = nil
      @locked_ruby_version    = nil
      @new_platform = nil

      if lockfile && File.exist?(lockfile)
        @lockfile_contents = Bundler.read_file(lockfile)
        @locked_gems = LockfileParser.new(@lockfile_contents)
        @locked_platforms = @locked_gems.platforms
        @platforms = @locked_platforms.dup
        @locked_bundler_version = @locked_gems.bundler_version
        @locked_ruby_version = @locked_gems.ruby_version
        @originally_locked_specs = SpecSet.new(@locked_gems.specs)

        if unlock != true
          @locked_deps    = @locked_gems.dependencies
          @locked_specs   = @originally_locked_specs
          @locked_sources = @locked_gems.sources
        else
          @unlock         = {}
          @locked_deps    = {}
          @locked_specs   = SpecSet.new([])
          @locked_sources = []
        end
      else
        @unlock         = {}
        @platforms      = []
        @locked_gems    = nil
        @locked_deps    = {}
        @locked_specs   = SpecSet.new([])
        @originally_locked_specs = @locked_specs
        @locked_sources = []
        @locked_platforms = []
      end

      locked_gem_sources = @locked_sources.select {|s| s.is_a?(Source::Rubygems) }
      @multisource_allowed = locked_gem_sources.size == 1 && locked_gem_sources.first.multiple_remotes? && Bundler.frozen_bundle?

      if @multisource_allowed
        unless sources.aggregate_global_source?
          msg = "Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. Make sure you run `bundle install` in non frozen mode and commit the result to make your lockfile secure."

          Bundler::SharedHelpers.major_deprecation 2, msg
        end

        @sources.merged_gem_lockfile_sections!(locked_gem_sources.first)
      end

      @unlock[:sources] ||= []
      @unlock[:ruby] ||= if @ruby_version && locked_ruby_version_object
        @ruby_version.diff(locked_ruby_version_object)
      end
      @unlocking ||= @unlock[:ruby] ||= (!@locked_ruby_version ^ !@ruby_version)

      add_current_platform unless current_ruby_platform_locked? || Bundler.frozen_bundle?

      converge_path_sources_to_gemspec_sources
      @path_changes = converge_paths
      @source_changes = converge_sources

      if @unlock[:conservative]
        @unlock[:gems] ||= @dependencies.map(&:name)
      else
        eager_unlock = (@unlock[:gems] || []).map {|name| Dependency.new(name, ">= 0") }
        @unlock[:gems] = @locked_specs.for(eager_unlock, false, platforms).map(&:name).uniq
      end

      @dependency_changes = converge_dependencies
      @local_changes = converge_locals

      @requires = compute_requires
    end

    def gem_version_promoter
      @gem_version_promoter ||= GemVersionPromoter.new(@originally_locked_specs, @unlock[:gems])
    end

    def resolve_only_locally!
      @remote = false
      sources.local_only!
      resolve
    end

    def resolve_prefering_local!
      @prefer_local = true
      @remote = true
      sources.remote!
      resolve
    end

    def resolve_with_cache!
      sources.cached!
      resolve
    end

    def resolve_remotely!
      @remote = true
      sources.remote!
      resolve
    end

    # For given dependency list returns a SpecSet with Gemspec of all the required
    # dependencies.
    #  1. The method first resolves the dependencies specified in Gemfile
    #  2. After that it tries and fetches gemspec of resolved dependencies
    #
    # @return [Bundler::SpecSet]
    def specs
      @specs ||= materialize(requested_dependencies)
    end

    def new_specs
      specs - @locked_specs
    end

    def removed_specs
      @locked_specs - specs
    end

    def missing_specs
      resolve.materialize(requested_dependencies).missing_specs
    end

    def missing_specs?
      missing = missing_specs
      return false if missing.empty?
      Bundler.ui.debug "The definition is missing #{missing.map(&:full_name)}"
      true
    rescue BundlerError => e
      @resolve = nil
      @resolver = nil
      @specs = nil
      @gem_version_promoter = nil

      Bundler.ui.debug "The definition is missing dependencies, failed to resolve & materialize locally (#{e})"
      true
    end

    def requested_specs
      specs_for(requested_groups)
    end

    def requested_dependencies
      dependencies_for(requested_groups)
    end

    def current_dependencies
      dependencies.select do |d|
        d.should_include? && !d.gem_platforms([generic_local_platform]).empty?
      end
    end

    def locked_dependencies
      @locked_deps.values
    end

    def new_deps
      @new_deps ||= @dependencies - locked_dependencies
    end

    def deleted_deps
      @deleted_deps ||= locked_dependencies - @dependencies
    end

    def specs_for(groups)
      return specs if groups.empty?
      deps = dependencies_for(groups)
      materialize(deps)
    end

    def dependencies_for(groups)
      groups.map!(&:to_sym)
      current_dependencies.reject do |d|
        (d.groups & groups).empty?
      end
    end

    # Resolve all the dependencies specified in Gemfile. It ensures that
    # dependencies that have been already resolved via locked file and are fresh
    # are reused when resolving dependencies
    #
    # @return [SpecSet] resolved dependencies
    def resolve
      @resolve ||= if Bundler.frozen_bundle?
        Bundler.ui.debug "Frozen, using resolution from the lockfile"
        @locked_specs
      elsif !unlocking? && nothing_changed?
        if deleted_deps.any?
          Bundler.ui.debug("Some dependencies were deleted, using a subset of the resolution from the lockfile")
          SpecSet.new(filter_specs(@locked_specs, @dependencies - deleted_deps))
        else
          Bundler.ui.debug("Found no changes, using resolution from the lockfile")
          if @locked_gems.may_include_redundant_platform_specific_gems?
            SpecSet.new(filter_specs(@locked_specs, @dependencies))
          else
            @locked_specs
          end
        end
      else
        Bundler.ui.debug("Found changes from the lockfile, re-resolving dependencies because #{change_reason}")
        resolver.start(expanded_dependencies)
      end
    end

    def spec_git_paths
      sources.git_sources.map {|s| File.realpath(s.path) if File.exist?(s.path) }.compact
    end

    def groups
      dependencies.map(&:groups).flatten.uniq
    end

    def lock(file, preserve_unknown_sections = false)
      return if Definition.no_lock

      contents = to_lock

      # Convert to \r\n if the existing lock has them
      # i.e., Windows with `git config core.autocrlf=true`
      contents.gsub!(/\n/, "\r\n") if @lockfile_contents.match("\r\n")

      if @locked_bundler_version
        locked_major = @locked_bundler_version.segments.first
        current_major = Gem::Version.create(Bundler::VERSION).segments.first

        updating_major = locked_major < current_major
      end

      preserve_unknown_sections ||= !updating_major && (Bundler.frozen_bundle? || !(unlocking? || @unlocking_bundler))

      return if file && File.exist?(file) && lockfiles_equal?(@lockfile_contents, contents, preserve_unknown_sections)

      if Bundler.frozen_bundle?
        Bundler.ui.error "Cannot write a changed lockfile while frozen."
        return
      end

      SharedHelpers.filesystem_access(file) do |p|
        File.open(p, "wb") {|f| f.puts(contents) }
      end
    end

    def locked_ruby_version
      return unless ruby_version
      if @unlock[:ruby] || !@locked_ruby_version
        Bundler::RubyVersion.system
      else
        @locked_ruby_version
      end
    end

    def locked_ruby_version_object
      return unless @locked_ruby_version
      @locked_ruby_version_object ||= begin
        unless version = RubyVersion.from_string(@locked_ruby_version)
          raise LockfileError, "The Ruby version #{@locked_ruby_version} from " \
            "#{@lockfile} could not be parsed. " \
            "Try running bundle update --ruby to resolve this."
        end
        version
      end
    end

    def to_lock
      require_relative "lockfile_generator"
      LockfileGenerator.generate(self)
    end

    def ensure_equivalent_gemfile_and_lockfile(explicit_flag = false)
      msg = String.new
      msg << "You are trying to install in deployment mode after changing\n" \
             "your Gemfile. Run `bundle install` elsewhere and add the\n" \
             "updated #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)} to version control."

      unless explicit_flag
        suggested_command = if Bundler.settings.locations("frozen").keys.&([:global, :local]).any?
          "bundle config unset frozen"
        elsif Bundler.settings.locations("deployment").keys.&([:global, :local]).any?
          "bundle config unset deployment"
        end
        msg << "\n\nIf this is a development machine, remove the #{Bundler.default_gemfile} " \
               "freeze \nby running `#{suggested_command}`." if suggested_command
      end

      added =   []
      deleted = []
      changed = []

      new_platforms = @platforms - @locked_platforms
      deleted_platforms = @locked_platforms - @platforms
      added.concat new_platforms.map {|p| "* platform: #{p}" }
      deleted.concat deleted_platforms.map {|p| "* platform: #{p}" }

      added.concat new_deps.map {|d| "* #{pretty_dep(d)}" } if new_deps.any?
      deleted.concat deleted_deps.map {|d| "* #{pretty_dep(d)}" } if deleted_deps.any?

      both_sources = Hash.new {|h, k| h[k] = [] }
      @dependencies.each {|d| both_sources[d.name][0] = d }

      locked_dependencies.each do |d|
        next if !Bundler.feature_flag.bundler_3_mode? && @locked_specs[d.name].empty?

        both_sources[d.name][1] = d
      end

      both_sources.each do |name, (dep, lock_dep)|
        next if dep.nil? || lock_dep.nil?

        gemfile_source = dep.source || sources.default_source
        lock_source = lock_dep.source || sources.default_source
        next if lock_source.include?(gemfile_source)

        gemfile_source_name = dep.source ? gemfile_source.identifier : "no specified source"
        lockfile_source_name = lock_dep.source ? lock_source.identifier : "no specified source"
        changed << "* #{name} from `#{lockfile_source_name}` to `#{gemfile_source_name}`"
      end

      reason = change_reason
      msg << "\n\n#{reason.split(", ").map(&:capitalize).join("\n")}" unless reason.strip.empty?
      msg << "\n\nYou have added to the Gemfile:\n" << added.join("\n") if added.any?
      msg << "\n\nYou have deleted from the Gemfile:\n" << deleted.join("\n") if deleted.any?
      msg << "\n\nYou have changed in the Gemfile:\n" << changed.join("\n") if changed.any?
      msg << "\n"

      raise ProductionError, msg if added.any? || deleted.any? || changed.any? || !nothing_changed?
    end

    def validate_runtime!
      validate_ruby!
      validate_platforms!
    end

    def validate_ruby!
      return unless ruby_version

      if diff = ruby_version.diff(Bundler::RubyVersion.system)
        problem, expected, actual = diff

        msg = case problem
              when :engine
                "Your Ruby engine is #{actual}, but your Gemfile specified #{expected}"
              when :version
                "Your Ruby version is #{actual}, but your Gemfile specified #{expected}"
              when :engine_version
                "Your #{Bundler::RubyVersion.system.engine} version is #{actual}, but your Gemfile specified #{ruby_version.engine} #{expected}"
              when :patchlevel
                if !expected.is_a?(String)
                  "The Ruby patchlevel in your Gemfile must be a string"
                else
                  "Your Ruby patchlevel is #{actual}, but your Gemfile specified #{expected}"
                end
        end

        raise RubyVersionMismatch, msg
      end
    end

    def validate_platforms!
      return if current_platform_locked?

      raise ProductionError, "Your bundle only supports platforms #{@platforms.map(&:to_s)} " \
        "but your local platform is #{Bundler.local_platform}. " \
        "Add the current platform to the lockfile with\n`bundle lock --add-platform #{Bundler.local_platform}` and try again."
    end

    def add_platform(platform)
      @new_platform ||= !@platforms.include?(platform)
      @platforms |= [platform]
    end

    def remove_platform(platform)
      return if @platforms.delete(Gem::Platform.new(platform))
      raise InvalidOption, "Unable to remove the platform `#{platform}` since the only platforms are #{@platforms.join ", "}"
    end

    def most_specific_locked_platform
      @platforms.min_by do |bundle_platform|
        platform_specificity_match(bundle_platform, local_platform)
      end
    end

    attr_reader :sources
    private :sources

    def nothing_changed?
      !@source_changes && !@dependency_changes && !@new_platform && !@path_changes && !@local_changes
    end

    def unlocking?
      @unlocking
    end

    private

    def resolver
      @resolver ||= begin
        last_resolve = converge_locked_specs
        remove_ruby_from_platforms_if_necessary!(current_dependencies)
        Resolver.new(source_requirements, last_resolve, gem_version_promoter, additional_base_requirements_for_resolve(last_resolve), platforms)
      end
    end

    def expanded_dependencies
      @expanded_dependencies ||= dependencies + metadata_dependencies
    end

    def filter_specs(specs, deps)
      SpecSet.new(specs).for(deps, false, platforms)
    end

    def materialize(dependencies)
      specs = resolve.materialize(dependencies)
      missing_specs = specs.missing_specs

      if missing_specs.any?
        missing_specs.each do |s|
          locked_gem = @locked_specs[s.name].last
          next if locked_gem.nil? || locked_gem.version != s.version || !@remote
          raise GemNotFound, "Your bundle is locked to #{locked_gem} from #{locked_gem.source}, but that version can " \
                             "no longer be found in that source. That means the author of #{locked_gem} has removed it. " \
                             "You'll need to update your bundle to a version other than #{locked_gem} that hasn't been " \
                             "removed in order to install."
        end

        missing_specs_list = missing_specs.group_by(&:source).map do |source, missing_specs_for_source|
          "#{missing_specs_for_source.map(&:full_name).join(", ")} in #{source}"
        end

        raise GemNotFound, "Could not find #{missing_specs_list.join(" nor ")}"
      end

      loop do
        incomplete_specs = specs.incomplete_specs
        break if incomplete_specs.empty?

        Bundler.ui.debug("The lockfile does not have all gems needed for the current platform though, Bundler will still re-resolve dependencies")
        @resolve = resolver.start(expanded_dependencies, :exclude_specs => incomplete_specs)
        specs = resolve.materialize(dependencies)
      end

      bundler = sources.metadata_source.specs.search(Gem::Dependency.new("bundler", VERSION)).last
      specs["bundler"] = bundler

      specs
    end

    def precompute_source_requirements_for_indirect_dependencies?
      @remote && sources.non_global_rubygems_sources.all?(&:dependency_api_available?) && !sources.aggregate_global_source?
    end

    def pin_locally_available_names(source_requirements)
      source_requirements.each_with_object({}) do |(name, original_source), new_source_requirements|
        local_source = original_source.dup
        local_source.local_only!

        new_source_requirements[name] = if local_source.specs.search(name).any?
          local_source
        else
          original_source
        end
      end
    end

    def current_ruby_platform_locked?
      return false unless generic_local_platform == Gem::Platform::RUBY
      return false if Bundler.settings[:force_ruby_platform] && !@platforms.include?(Gem::Platform::RUBY)

      current_platform_locked?
    end

    def current_platform_locked?
      @platforms.any? do |bundle_platform|
        MatchPlatform.platforms_match?(bundle_platform, Bundler.local_platform)
      end
    end

    def add_current_platform
      add_platform(local_platform)
    end

    def change_reason
      if unlocking?
        unlock_reason = @unlock.reject {|_k, v| Array(v).empty? }.map do |k, v|
          if v == true
            k.to_s
          else
            v = Array(v)
            "#{k}: (#{v.join(", ")})"
          end
        end.join(", ")
        return "bundler is unlocking #{unlock_reason}"
      end
      [
        [@source_changes, "the list of sources changed"],
        [@dependency_changes, "the dependencies in your gemfile changed"],
        [@new_platform, "you added a new platform to your gemfile"],
        [@path_changes, "the gemspecs for path gems changed"],
        [@local_changes, "the gemspecs for git local gems changed"],
      ].select(&:first).map(&:last).join(", ")
    end

    def pretty_dep(dep)
      SharedHelpers.pretty_dependency(dep)
    end

    # Check if the specs of the given source changed
    # according to the locked source.
    def specs_changed?(source)
      locked = @locked_sources.find {|s| s == source }

      !locked || dependencies_for_source_changed?(source, locked) || specs_for_source_changed?(source)
    end

    def dependencies_for_source_changed?(source, locked_source = source)
      deps_for_source = @dependencies.select {|s| s.source == source }
      locked_deps_for_source = locked_dependencies.select {|dep| dep.source == locked_source }

      deps_for_source.uniq.sort != locked_deps_for_source.sort
    end

    def specs_for_source_changed?(source)
      locked_index = Index.new
      locked_index.use(@locked_specs.select {|s| source.can_lock?(s) })

      # order here matters, since Index#== is checking source.specs.include?(locked_index)
      locked_index != source.specs
    rescue PathError, GitError => e
      Bundler.ui.debug "Assuming that #{source} has not changed since fetching its specs errored (#{e})"
      false
    end

    # Get all locals and override their matching sources.
    # Return true if any of the locals changed (for example,
    # they point to a new revision) or depend on new specs.
    def converge_locals
      locals = []

      Bundler.settings.local_overrides.map do |k, v|
        spec   = @dependencies.find {|s| s.name == k }
        source = spec && spec.source
        if source && source.respond_to?(:local_override!)
          source.unlock! if @unlock[:gems].include?(spec.name)
          locals << [source, source.local_override!(v)]
        end
      end

      sources_with_changes = locals.select do |source, changed|
        changed || specs_changed?(source)
      end.map(&:first)
      !sources_with_changes.each {|source| @unlock[:sources] << source.name }.empty?
    end

    def converge_paths
      sources.path_sources.any? do |source|
        specs_changed?(source)
      end
    end

    def converge_path_source_to_gemspec_source(source)
      return source unless source.instance_of?(Source::Path)
      gemspec_source = sources.path_sources.find {|s| s.is_a?(Source::Gemspec) && s.as_path_source == source }
      gemspec_source || source
    end

    def converge_path_sources_to_gemspec_sources
      @locked_sources.map! do |source|
        converge_path_source_to_gemspec_source(source)
      end
      @locked_specs.each do |spec|
        spec.source &&= converge_path_source_to_gemspec_source(spec.source)
      end
      @locked_deps.each do |_, dep|
        dep.source &&= converge_path_source_to_gemspec_source(dep.source)
      end
    end

    def converge_sources
      # Replace the sources from the Gemfile with the sources from the Gemfile.lock,
      # if they exist in the Gemfile.lock and are `==`. If you can't find an equivalent
      # source in the Gemfile.lock, use the one from the Gemfile.
      changes = sources.replace_sources!(@locked_sources)

      sources.all_sources.each do |source|
        # If the source is unlockable and the current command allows an unlock of
        # the source (for example, you are doing a `bundle update <foo>` of a git-pinned
        # gem), unlock it. For git sources, this means to unlock the revision, which
        # will cause the `ref` used to be the most recent for the branch (or master) if
        # an explicit `ref` is not used.
        if source.respond_to?(:unlock!) && @unlock[:sources].include?(source.name)
          source.unlock!
          changes = true
        end
      end

      changes
    end

    def converge_dependencies
      changes = false

      @dependencies.each do |dep|
        if dep.source
          dep.source = sources.get(dep.source)
        end

        unless locked_dep = @locked_deps[dep.name]
          changes = true
          next
        end

        # Gem::Dependency#== matches Gem::Dependency#type. As the lockfile
        # doesn't carry a notion of the dependency type, if you use
        # add_development_dependency in a gemspec that's loaded with the gemspec
        # directive, the lockfile dependencies and resolved dependencies end up
        # with a mismatch on #type. Work around that by setting the type on the
        # dep from the lockfile.
        locked_dep.instance_variable_set(:@type, dep.type)

        # We already know the name matches from the hash lookup
        # so we only need to check the requirement now
        changes ||= dep.requirement != locked_dep.requirement
      end

      changes
    end

    # Remove elements from the locked specs that are expired. This will most
    # commonly happen if the Gemfile has changed since the lockfile was last
    # generated
    def converge_locked_specs
      converged = converge_specs(@locked_specs)

      resolve = SpecSet.new(converged.reject {|s| @unlock[:gems].include?(s.name) })

      diff = nil

      # Now, we unlock any sources that do not have anymore gems pinned to it
      sources.all_sources.each do |source|
        next unless source.respond_to?(:unlock!)

        unless resolve.any? {|s| s.source == source }
          diff ||= @locked_specs.to_a - resolve.to_a
          source.unlock! if diff.any? {|s| s.source == source }
        end
      end

      resolve
    end

    def converge_specs(specs)
      converged = []

      deps = @dependencies.select do |dep|
        specs[dep].any? {|s| s.satisfies?(dep) && (!dep.source || s.source.include?(dep.source)) }
      end

      @specs_that_changed_sources = []

      specs.each do |s|
        dep = @dependencies.find {|d| s.satisfies?(d) }

        # Replace the locked dependency's source with the equivalent source from the Gemfile
        s.source = if dep && dep.source
          gemfile_source = dep.source
          lockfile_source = s.source

          @specs_that_changed_sources << s if gemfile_source != lockfile_source

          gemfile_source
        else
          sources.get_with_fallback(s.source)
        end

        next if @unlock[:sources].include?(s.source.name)

        # Path sources have special logic
        if s.source.instance_of?(Source::Path) || s.source.instance_of?(Source::Gemspec)
          new_specs = begin
            s.source.specs
          rescue PathError, GitError
            # if we won't need the source (according to the lockfile),
            # don't error if the path/git source isn't available
            next if specs.
                    for(requested_dependencies, false).
                    none? {|locked_spec| locked_spec.source == s.source }

            raise
          end

          new_spec = new_specs[s].first

          # If the spec is no longer in the path source, unlock it. This
          # commonly happens if the version changed in the gemspec
          next unless new_spec

          s.dependencies.replace(new_spec.dependencies)
        end

        if dep.nil? && requested_dependencies.find {|d| s.name == d.name }
          @unlock[:gems] << s.name
        else
          converged << s
        end
      end

      filter_specs(converged, deps)
    end

    def metadata_dependencies
      @metadata_dependencies ||= [
        Dependency.new("Ruby\0", Gem.ruby_version),
        Dependency.new("RubyGems\0", Gem::VERSION),
      ]
    end

    def source_requirements
      # Record the specs available in each gem's source, so that those
      # specs will be available later when the resolver knows where to
      # look for that gemspec (or its dependencies)
      source_requirements = if precompute_source_requirements_for_indirect_dependencies?
        all_requirements = source_map.all_requirements
        all_requirements = pin_locally_available_names(all_requirements) if @prefer_local
        { :default => sources.default_source }.merge(all_requirements)
      else
        { :default => Source::RubygemsAggregate.new(sources, source_map) }.merge(source_map.direct_requirements)
      end
      source_requirements.merge!(source_map.locked_requirements) unless @remote
      metadata_dependencies.each do |dep|
        source_requirements[dep.name] = sources.metadata_source
      end
      source_requirements[:default_bundler] = source_requirements["bundler"] || sources.default_source
      source_requirements["bundler"] = sources.metadata_source # needs to come last to override
      verify_changed_sources!
      source_requirements
    end

    def verify_changed_sources!
      @specs_that_changed_sources.each do |s|
        if s.source.specs.search(s.name).empty?
          raise GemNotFound, "Could not find gem '#{s.name}' in #{s.source}"
        end
      end
    end

    def requested_groups
      values = groups - Bundler.settings[:without] - @optional_groups + Bundler.settings[:with]
      values &= Bundler.settings[:only] unless Bundler.settings[:only].empty?
      values
    end

    def lockfiles_equal?(current, proposed, preserve_unknown_sections)
      if preserve_unknown_sections
        sections_to_ignore = LockfileParser.sections_to_ignore(@locked_bundler_version)
        sections_to_ignore += LockfileParser.unknown_sections_in_lockfile(current)
        sections_to_ignore += LockfileParser::ENVIRONMENT_VERSION_SECTIONS
        pattern = /#{Regexp.union(sections_to_ignore)}\n(\s{2,}.*\n)+/
        whitespace_cleanup = /\n{2,}/
        current = current.gsub(pattern, "\n").gsub(whitespace_cleanup, "\n\n").strip
        proposed = proposed.gsub(pattern, "\n").gsub(whitespace_cleanup, "\n\n").strip
      end
      current == proposed
    end

    def compute_requires
      dependencies.reduce({}) do |requires, dep|
        next requires unless dep.should_include?
        requires[dep.name] = Array(dep.autorequire || dep.name).map do |file|
          # Allow `require: true` as an alias for `require: <name>`
          file == true ? dep.name : file
        end
        requires
      end
    end

    def additional_base_requirements_for_resolve(last_resolve)
      return [] unless @locked_gems && unlocking? && !sources.expired_sources?(@locked_gems.sources)
      converge_specs(@originally_locked_specs - last_resolve).map do |locked_spec|
        Dependency.new(locked_spec.name, ">= #{locked_spec.version}")
      end.uniq
    end

    def remove_ruby_from_platforms_if_necessary!(dependencies)
      return if Bundler.frozen_bundle? ||
                Bundler.local_platform == Gem::Platform::RUBY ||
                !platforms.include?(Gem::Platform::RUBY) ||
                (@new_platform && platforms.last == Gem::Platform::RUBY) ||
                !@originally_locked_specs.incomplete_ruby_specs?(dependencies)

      remove_platform(Gem::Platform::RUBY)
      add_current_platform
    end

    def source_map
      @source_map ||= SourceMap.new(sources, dependencies, @locked_specs)
    end
  end
end
