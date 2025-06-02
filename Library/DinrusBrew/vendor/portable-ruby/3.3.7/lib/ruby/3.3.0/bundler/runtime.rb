# frozen_string_literal: true

module Bundler
  class Runtime
    include SharedHelpers

    def initialize(root, definition)
      @root = root
      @definition = definition
    end

    def setup(*groups)
      @definition.ensure_equivalent_gemfile_and_lockfile

      # Has to happen first
      clean_load_path

      specs = @definition.specs_for(groups)

      SharedHelpers.set_bundle_environment
      Bundler.rubygems.replace_entrypoints(specs)

      # Activate the specs
      load_paths = specs.map do |spec|
        check_for_activated_spec!(spec)

        Bundler.rubygems.mark_loaded(spec)
        spec.load_paths.reject {|path| $LOAD_PATH.include?(path) }
      end.reverse.flatten

      Gem.add_to_load_path(*load_paths)

      setup_manpath

      lock(preserve_unknown_sections: true)

      self
    end

    def require(*groups)
      groups.map!(&:to_sym)
      groups = [:default] if groups.empty?

      @definition.dependencies.each do |dep|
        # Skip the dependency if it is not in any of the requested groups, or
        # not for the current platform, or doesn't match the gem constraints.
        next unless (dep.groups & groups).any? && dep.should_include?

        required_file = nil

        begin
          # Loop through all the specified autorequires for the
          # dependency. If there are none, use the dependency's name
          # as the autorequire.
          Array(dep.autorequire || dep.name).each do |file|
            # Allow `require: true` as an alias for `require: <name>`
            file = dep.name if file == true
            required_file = file
            begin
              Kernel.require file
            rescue RuntimeError => e
              raise e if e.is_a?(LoadError) # we handle this a little later
              raise Bundler::GemRequireError.new e,
                "There was an error while trying to load the gem '#{file}'."
            end
          end
        rescue LoadError => e
          raise if dep.autorequire || e.path != required_file

          if dep.autorequire.nil? && dep.name.include?("-")
            begin
              namespaced_file = dep.name.tr("-", "/")
              Kernel.require namespaced_file
            rescue LoadError => e
              raise if e.path != namespaced_file
            end
          end
        end
      end
    end

    def self.definition_method(meth)
      define_method(meth) do
        raise ArgumentError, "no definition when calling Runtime##{meth}" unless @definition
        @definition.send(meth)
      end
    end
    private_class_method :definition_method

    definition_method :requested_specs
    definition_method :specs
    definition_method :dependencies
    definition_method :current_dependencies
    definition_method :requires

    def lock(opts = {})
      return if @definition.no_resolve_needed?
      @definition.lock(opts[:preserve_unknown_sections])
    end

    alias_method :gems, :specs

    def cache(custom_path = nil, local = false)
      cache_path = Bundler.app_cache(custom_path)
      SharedHelpers.filesystem_access(cache_path) do |p|
        FileUtils.mkdir_p(p)
      end unless File.exist?(cache_path)

      Bundler.ui.info "Updating files in #{Bundler.settings.app_cache_path}"

      specs_to_cache = if Bundler.settings[:cache_all_platforms]
        @definition.resolve.materialized_for_all_platforms
      else
        begin
          specs
        rescue GemNotFound
          if local
            Bundler.ui.warn "Some gems seem to be missing from your #{Bundler.settings.app_cache_path} directory."
          end

          raise
        end
      end

      specs_to_cache.each do |spec|
        next if spec.name == "bundler"
        next if spec.source.is_a?(Source::Gemspec)
        spec.source.cache(spec, custom_path) if spec.source.respond_to?(:cache)
      end

      prune_cache(cache_path) unless Bundler.settings[:no_prune]
    end

    def prune_cache(cache_path)
      SharedHelpers.filesystem_access(cache_path) do |p|
        FileUtils.mkdir_p(p)
      end unless File.exist?(cache_path)
      resolve = @definition.resolve
      prune_gem_cache(resolve, cache_path)
      prune_git_and_path_cache(resolve, cache_path)
    end

    def clean(dry_run = false)
      gem_bins             = Dir["#{Gem.dir}/bin/*"]
      git_dirs             = Dir["#{Gem.dir}/bundler/gems/*"]
      git_cache_dirs       = Dir["#{Gem.dir}/cache/bundler/git/*"]
      gem_dirs             = Dir["#{Gem.dir}/gems/*"]
      gem_files            = Dir["#{Gem.dir}/cache/*.gem"]
      gemspec_files        = Dir["#{Gem.dir}/specifications/*.gemspec"]
      extension_dirs       = Dir["#{Gem.dir}/extensions/*/*/*"] + Dir["#{Gem.dir}/bundler/gems/extensions/*/*/*"]
      spec_gem_paths       = []
      # need to keep git sources around
      spec_git_paths       = @definition.spec_git_paths
      spec_git_cache_dirs  = []
      spec_gem_executables = []
      spec_cache_paths     = []
      spec_gemspec_paths   = []
      spec_extension_paths = []
      Bundler.rubygems.add_default_gems_to(specs).values.each do |spec|
        spec_gem_paths << spec.full_gem_path
        # need to check here in case gems are nested like for the rails git repo
        md = %r{(.+bundler/gems/.+-[a-f0-9]{7,12})}.match(spec.full_gem_path)
        spec_git_paths << md[1] if md
        spec_gem_executables << spec.executables.collect do |executable|
          e = "#{Bundler.rubygems.gem_bindir}/#{executable}"
          [e, "#{e}.bat"]
        end
        spec_cache_paths << spec.cache_file
        spec_gemspec_paths << spec.spec_file
        spec_extension_paths << spec.extension_dir if spec.respond_to?(:extension_dir)
        spec_git_cache_dirs << spec.source.cache_path.to_s if spec.source.is_a?(Bundler::Source::Git)
      end
      spec_gem_paths.uniq!
      spec_gem_executables.flatten!

      stale_gem_bins       = gem_bins - spec_gem_executables
      stale_git_dirs       = git_dirs - spec_git_paths - ["#{Gem.dir}/bundler/gems/extensions"]
      stale_git_cache_dirs = git_cache_dirs - spec_git_cache_dirs
      stale_gem_dirs       = gem_dirs - spec_gem_paths
      stale_gem_files      = gem_files - spec_cache_paths
      stale_gemspec_files  = gemspec_files - spec_gemspec_paths
      stale_extension_dirs = extension_dirs - spec_extension_paths

      removed_stale_gem_dirs = stale_gem_dirs.collect {|dir| remove_dir(dir, dry_run) }
      removed_stale_git_dirs = stale_git_dirs.collect {|dir| remove_dir(dir, dry_run) }
      output = removed_stale_gem_dirs + removed_stale_git_dirs

      unless dry_run
        stale_files = stale_gem_bins + stale_gem_files + stale_gemspec_files
        stale_files.each do |file|
          SharedHelpers.filesystem_access(File.dirname(file)) do |_p|
            FileUtils.rm(file) if File.exist?(file)
          end
        end

        stale_dirs = stale_git_cache_dirs + stale_extension_dirs
        stale_dirs.each do |stale_dir|
          SharedHelpers.filesystem_access(stale_dir) do |dir|
            FileUtils.rm_rf(dir) if File.exist?(dir)
          end
        end
      end

      output
    end

    private

    def prune_gem_cache(resolve, cache_path)
      cached = Dir["#{cache_path}/*.gem"]

      cached = cached.delete_if do |path|
        spec = Bundler.rubygems.spec_from_gem path

        resolve.any? do |s|
          s.name == spec.name && s.version == spec.version && !s.source.is_a?(Bundler::Source::Git)
        end
      end

      if cached.any?
        Bundler.ui.info "Removing outdated .gem files from #{Bundler.settings.app_cache_path}"

        cached.each do |path|
          Bundler.ui.info "  * #{File.basename(path)}"
          File.delete(path)
        end
      end
    end

    def prune_git_and_path_cache(resolve, cache_path)
      cached = Dir["#{cache_path}/*/.bundlecache"]

      cached = cached.delete_if do |path|
        name = File.basename(File.dirname(path))

        resolve.any? do |s|
          source = s.source
          source.respond_to?(:app_cache_dirname) && source.app_cache_dirname == name
        end
      end

      if cached.any?
        Bundler.ui.info "Removing outdated git and path gems from #{Bundler.settings.app_cache_path}"

        cached.each do |path|
          path = File.dirname(path)
          Bundler.ui.info "  * #{File.basename(path)}"
          FileUtils.rm_rf(path)
        end
      end
    end

    def setup_manpath
      # Add man/ subdirectories from activated bundles to MANPATH for man(1)
      manuals = $LOAD_PATH.map do |path|
        man_subdir = path.sub(/lib$/, "man")
        man_subdir unless Dir[man_subdir + "/man?/"].empty?
      end.compact

      return if manuals.empty?
      Bundler::SharedHelpers.set_env "MANPATH", manuals.concat(
        ENV["MANPATH"] ? ENV["MANPATH"].to_s.split(File::PATH_SEPARATOR) : [""]
      ).uniq.join(File::PATH_SEPARATOR)
    end

    def remove_dir(dir, dry_run)
      full_name = Pathname.new(dir).basename.to_s

      parts    = full_name.split("-")
      name     = parts[0..-2].join("-")
      version  = parts.last
      output   = "#{name} (#{version})"

      if dry_run
        Bundler.ui.info "Would have removed #{output}"
      else
        Bundler.ui.info "Removing #{output}"
        FileUtils.rm_rf(dir)
      end

      output
    end

    def check_for_activated_spec!(spec)
      return unless activated_spec = Bundler.rubygems.loaded_specs(spec.name)
      return if activated_spec.version == spec.version

      suggestion = if activated_spec.default_gem?
        "Since #{spec.name} is a default gem, you can either remove your dependency on it" \
        " or try updating to a newer version of bundler that supports #{spec.name} as a default gem."
      else
        "Prepending `bundle exec` to your command may solve this."
      end

      e = Gem::LoadError.new "You have already activated #{activated_spec.name} #{activated_spec.version}, " \
                             "but your Gemfile requires #{spec.name} #{spec.version}. #{suggestion}"
      e.name = spec.name
      e.requirement = Gem::Requirement.new(spec.version.to_s)
      raise e
    end
  end
end
