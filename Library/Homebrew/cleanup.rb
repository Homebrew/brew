# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "utils/bottles"

require "attrable"
require "formula"
require "cask/cask_loader"

module Homebrew
  # Helper class for cleaning up the Homebrew cache.
  class Cleanup
    CLEANUP_DEFAULT_DAYS = Homebrew::EnvConfig.cleanup_periodic_full_days.to_i.freeze
    private_constant :CLEANUP_DEFAULT_DAYS

    class << self
      sig { params(pathname: Pathname).returns(T::Boolean) }
      def incomplete?(pathname)
        pathname.extname.end_with?(".incomplete")
      end

      sig { params(pathname: Pathname).returns(T::Boolean) }
      def nested_cache?(pathname)
        pathname.directory? && %w[
          cargo_cache
          go_cache
          go_mod_cache
          glide_home
          java_cache
          npm_cache
          pip_cache
          gclient_cache
        ].include?(pathname.basename.to_s)
      end

      sig { params(pathname: Pathname).returns(T::Boolean) }
      def go_cache_directory?(pathname)
        # Go makes its cache contents read-only to ensure cache integrity,
        # which makes sense but is something we need to undo for cleanup.
        pathname.directory? && %w[go_cache go_mod_cache].include?(pathname.basename.to_s)
      end

      sig { params(pathname: Pathname, days: T.nilable(Integer)).returns(T::Boolean) }
      def prune?(pathname, days)
        return false unless days
        return true if days.zero?
        return true if pathname.symlink? && !pathname.exist?

        days_ago = (DateTime.now - days).to_time
        pathname.mtime < days_ago && pathname.ctime < days_ago
      end

      sig { params(entry: { path: Pathname, type: T.nilable(Symbol) }, scrub: T::Boolean).returns(T::Boolean) }
      def stale?(entry, scrub: false)
        pathname = entry[:path]
        return false unless pathname.resolved_path.file?

        case entry[:type]
        when :api_source
          stale_api_source?(pathname, scrub)
        when :cask
          stale_cask?(pathname, scrub)
        when :gh_actions_artifact
          stale_gh_actions_artifact?(pathname, scrub)
        when :attestation
          stale_attestation?(pathname, scrub)
        else
          stale_formula?(pathname, scrub)
        end
      end

      private

      GH_ACTIONS_ARTIFACT_CLEANUP_DAYS = 3

      sig { params(pathname: Pathname, scrub: T::Boolean).returns(T::Boolean) }
      def stale_gh_actions_artifact?(pathname, scrub)
        scrub || prune?(pathname, GH_ACTIONS_ARTIFACT_CLEANUP_DAYS)
      end

      ATTESTATION_CLEANUP_DAYS = 3

      sig { params(pathname: Pathname, scrub: T::Boolean).returns(T::Boolean) }
      def stale_attestation?(pathname, scrub)
        scrub || prune?(pathname, ATTESTATION_CLEANUP_DAYS)
      end

      sig { params(pathname: Pathname, scrub: T::Boolean).returns(T::Boolean) }
      def stale_api_source?(pathname, scrub)
        return true if scrub

        org, repo, git_head, type, basename = pathname.each_filename.to_a.last(5)

        name = "#{org}/#{repo}/#{File.basename(T.must(basename), ".rb")}"
        package = if type == "Cask"
          begin
            Cask::CaskLoader.load(name)
          rescue Cask::CaskError
            nil
          end
        else
          begin
            Formulary.factory(name)
          rescue FormulaUnavailableError
            nil
          end
        end
        return true if package.nil?

        package.tap_git_head != git_head
      end

      sig { params(formula: Formula).returns(T::Set[String]) }
      def excluded_versions_from_cleanup(formula)
        @excluded_versions_from_cleanup ||= {}
        @excluded_versions_from_cleanup[formula.name] ||= begin
          eligible_kegs_for_cleanup = formula.eligible_kegs_for_cleanup(quiet: true)
          Set.new((formula.installed_kegs - eligible_kegs_for_cleanup).map { |keg| keg.version.to_s })
        end
      end

      sig { params(pathname: Pathname, scrub: T::Boolean).returns(T::Boolean) }
      def stale_formula?(pathname, scrub)
        return false unless HOMEBREW_CELLAR.directory?

        version = if HOMEBREW_BOTTLES_EXTNAME_REGEX.match?(to_s)
          begin
            Utils::Bottles.resolve_version(pathname).to_s
          rescue
            nil
          end
        end
        basename_str = pathname.basename.to_s

        version ||= basename_str[/\A.*(?:--.*?)*--(.*?)#{Regexp.escape(pathname.extname)}\Z/, 1]
        version ||= basename_str[/\A.*--?(.*?)#{Regexp.escape(pathname.extname)}\Z/, 1]

        return false if version.blank?

        version = Version.new(version)

        unless (formula_name = basename_str[/\A(.*?)(?:--.*?)*--?(?:#{Regexp.escape(version.to_s)})/, 1])
          return false
        end

        formula = begin
          Formulary.from_rack(HOMEBREW_CELLAR/formula_name)
        rescue FormulaUnavailableError, TapFormulaAmbiguityError
          nil
        end

        formula_excluded_versions_from_cleanup = nil
        if formula.blank? && formula_name.delete_suffix!("_bottle_manifest")
          formula = begin
            Formulary.from_rack(HOMEBREW_CELLAR/formula_name)
          rescue FormulaUnavailableError, TapFormulaAmbiguityError
            nil
          end

          return false if formula.blank?

          formula_excluded_versions_from_cleanup = excluded_versions_from_cleanup(formula)
          return false if formula_excluded_versions_from_cleanup.include?(version.to_s)

          # We can't determine an installed rebuild and parsing manifest version cannot be reliably done.
          return false unless formula.latest_version_installed?

          return true if (bottle = formula.bottle).blank?

          return version != GitHubPackages.version_rebuild(bottle.resource.version, bottle.rebuild)
        end

        return false if formula.blank?

        resource_name = basename_str[/\A.*?--(.*?)--?(?:#{Regexp.escape(version.to_s)})/, 1]

        stable = formula.stable
        if resource_name == "patch"
          patch_hashes = stable&.patches&.filter_map { _1.resource.version if _1.external? }
          return true unless patch_hashes&.include?(Checksum.new(version.to_s))
        elsif resource_name && stable && (resource_version = stable.resources[resource_name]&.version)
          return true if resource_version != version
        elsif (formula_excluded_versions_from_cleanup ||= excluded_versions_from_cleanup(formula).presence) &&
              formula_excluded_versions_from_cleanup.include?(version.to_s)
          return false
        elsif (formula.latest_version_installed? && formula.pkg_version.to_s != version) ||
              formula.pkg_version.to_s > version
          return true
        end

        return true if scrub && !formula.latest_version_installed?
        return true if Utils::Bottles.file_outdated?(formula, pathname)

        false
      end

      sig { params(pathname: Pathname, scrub: T::Boolean).returns(T::Boolean) }
      def stale_cask?(pathname, scrub)
        basename = pathname.basename
        return false unless (name = basename.to_s[/\A(.*?)--/, 1])

        cask = begin
          Cask::CaskLoader.load(name)
        rescue Cask::CaskError
          nil
        end

        return false if cask.blank?
        return true unless basename.to_s.match?(/\A#{Regexp.escape(name)}--#{Regexp.escape(cask.version)}\b/)
        return true if scrub && cask.installed_version != cask.version

        if cask.version.latest?
          cleanup_threshold = (DateTime.now - CLEANUP_DEFAULT_DAYS).to_time
          return pathname.mtime < cleanup_threshold && pathname.ctime < cleanup_threshold
        end

        false
      end
    end

    extend Attrable

    PERIODIC_CLEAN_FILE = (HOMEBREW_CACHE/".cleaned").freeze

    attr_predicate :dry_run?, :scrub?, :prune?
    attr_reader :args, :days, :cache, :disk_cleanup_size

    def initialize(*args, dry_run: false, scrub: false, days: nil, cache: HOMEBREW_CACHE)
      @disk_cleanup_size = 0
      @args = args
      @dry_run = dry_run
      @scrub = scrub
      @prune = days.present?
      @days = days || Homebrew::EnvConfig.cleanup_max_age_days.to_i
      @cache = cache
      @cleaned_up_paths = Set.new
    end

    def self.install_formula_clean!(formula, dry_run: false)
      return if Homebrew::EnvConfig.no_install_cleanup?
      return unless formula.latest_version_installed?
      return if skip_clean_formula?(formula)

      if dry_run
        ohai "Would run `brew cleanup #{formula}`"
      else
        ohai "Running `brew cleanup #{formula}`..."
      end

      puts_no_install_cleanup_disable_message_if_not_already!
      return if dry_run

      Cleanup.new.cleanup_formula(formula)
    end

    def self.puts_no_install_cleanup_disable_message
      return if Homebrew::EnvConfig.no_env_hints?
      return if Homebrew::EnvConfig.no_install_cleanup?

      puts "Disable this behaviour by setting HOMEBREW_NO_INSTALL_CLEANUP."
      puts "Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`)."
    end

    def self.puts_no_install_cleanup_disable_message_if_not_already!
      return if @puts_no_install_cleanup_disable_message_if_not_already

      puts_no_install_cleanup_disable_message
      @puts_no_install_cleanup_disable_message_if_not_already = true
    end

    def self.skip_clean_formula?(formula)
      no_cleanup_formula = Homebrew::EnvConfig.no_cleanup_formulae
      return false if no_cleanup_formula.blank?

      @skip_clean_formulae ||= no_cleanup_formula.split(",")
      @skip_clean_formulae.include?(formula.name) || @skip_clean_formulae.intersect?(formula.aliases)
    end

    def self.periodic_clean_due?
      return false if Homebrew::EnvConfig.no_install_cleanup?

      unless PERIODIC_CLEAN_FILE.exist?
        HOMEBREW_CACHE.mkpath
        FileUtils.touch PERIODIC_CLEAN_FILE
        return false
      end

      PERIODIC_CLEAN_FILE.mtime < (DateTime.now - CLEANUP_DEFAULT_DAYS).to_time
    end

    def self.periodic_clean!(dry_run: false)
      return if Homebrew::EnvConfig.no_install_cleanup?
      return unless periodic_clean_due?

      if dry_run
        oh1 "Would run `brew cleanup` which has not been run in the last #{CLEANUP_DEFAULT_DAYS} days"
      else
        oh1 "`brew cleanup` has not been run in the last #{CLEANUP_DEFAULT_DAYS} days, running now..."
      end

      puts_no_install_cleanup_disable_message
      return if dry_run

      Cleanup.new.clean!(quiet: true, periodic: true)
    end

    def clean!(quiet: false, periodic: false)
      if args.empty?
        Formula.installed
               .sort_by(&:name)
               .reject { |f| Cleanup.skip_clean_formula?(f) }
               .each do |formula|
          cleanup_formula(formula, quiet:, ds_store: false, cache_db: false)
        end

        if ENV["HOMEBREW_AUTOREMOVE"].present?
          opoo "HOMEBREW_AUTOREMOVE is now a no-op as it is the default behaviour. " \
               "Set HOMEBREW_NO_AUTOREMOVE=1 to disable it."
        end
        Cleanup.autoremove(dry_run: dry_run?) unless Homebrew::EnvConfig.no_autoremove?

        cleanup_cache
        cleanup_empty_api_source_directories
        cleanup_bootsnap
        cleanup_logs
        cleanup_lockfiles
        cleanup_python_site_packages
        prune_prefix_symlinks_and_directories

        unless dry_run?
          cleanup_cache_db
          rm_ds_store
          HOMEBREW_CACHE.mkpath
          FileUtils.touch PERIODIC_CLEAN_FILE
        end

        # Cleaning up Ruby needs to be done last to avoid requiring additional
        # files afterwards. Additionally, don't allow it on periodic cleans to
        # avoid having to try to do a `brew install` when we've just deleted
        # the running Ruby process...
        return if periodic

        cleanup_portable_ruby
      else
        args.each do |arg|
          formula = begin
            Formulary.resolve(arg)
          rescue FormulaUnavailableError, TapFormulaAmbiguityError
            nil
          end

          cask = begin
            Cask::CaskLoader.load(arg)
          rescue Cask::CaskError
            nil
          end

          if formula && Cleanup.skip_clean_formula?(formula)
            onoe "Refusing to clean #{formula} because it is listed in " \
                 "#{Tty.bold}HOMEBREW_NO_CLEANUP_FORMULAE#{Tty.reset}!"
          elsif formula
            cleanup_formula(formula)
          end
          cleanup_cask(cask) if cask
        end
      end
    end

    def unremovable_kegs
      @unremovable_kegs ||= []
    end

    def cleanup_formula(formula, quiet: false, ds_store: true, cache_db: true)
      formula.eligible_kegs_for_cleanup(quiet:)
             .each { cleanup_keg(_1) }
      cleanup_cache(Pathname.glob(cache/"#{formula.name}{_bottle_manifest,}--*").map { |path| { path:, type: nil } })
      rm_ds_store([formula.rack]) if ds_store
      cleanup_cache_db(formula.rack) if cache_db
      cleanup_lockfiles(FormulaLock.new(formula.name).path)
    end

    def cleanup_cask(cask, ds_store: true)
      cleanup_cache(Pathname.glob(cache/"Cask/#{cask.token}--*").map { |path| { path:, type: :cask } })
      rm_ds_store([cask.caskroom_path]) if ds_store
      cleanup_lockfiles(CaskLock.new(cask.token).path)
    end

    def cleanup_keg(keg)
      cleanup_path(keg) { keg.uninstall(raise_failures: true) }
    rescue Errno::EACCES, Errno::ENOTEMPTY => e
      opoo e.message
      unremovable_kegs << keg
    end

    def cleanup_logs
      return unless HOMEBREW_LOGS.directory?

      logs_days = [days, CLEANUP_DEFAULT_DAYS].min

      HOMEBREW_LOGS.subdirs.each do |dir|
        cleanup_path(dir) { FileUtils.rm_r(dir) } if self.class.prune?(dir, logs_days)
      end
    end

    def cache_files
      files = cache.directory? ? cache.children : []
      cask_files = (cache/"Cask").directory? ? (cache/"Cask").children : []
      api_source_files = (cache/"api-source").glob("*/*/*/*/*") # `<org>/<repo>/<git_head>/<type>/<token>.rb`
      gh_actions_artifacts = (cache/"gh-actions-artifact").directory? ? (cache/"gh-actions-artifact").children : []
      attestations = (cache/"attestation").directory? ? (cache/"attestation").children : []

      files.map { |path| { path:, type: nil } } +
        cask_files.map { |path| { path:, type: :cask } } +
        api_source_files.map { |path| { path:, type: :api_source } } +
        gh_actions_artifacts.map { |path| { path:, type: :gh_actions_artifact } } +
        attestations.map { |path| { path:, type: :attestation } }
    end

    def cleanup_empty_api_source_directories(directory = cache/"api-source")
      return if dry_run?
      return unless directory.directory?

      directory.each_child do |child|
        next unless child.directory?

        cleanup_empty_api_source_directories(child)
        child.rmdir if child.empty?
      end
    end

    def cleanup_unreferenced_downloads
      return if dry_run?
      return unless (cache/"downloads").directory?

      downloads = (cache/"downloads").children

      referenced_downloads = cache_files.map { |file| file[:path] }.select(&:symlink?).map(&:resolved_path)

      (downloads - referenced_downloads).each do |download|
        if self.class.incomplete?(download)
          begin
            DownloadLock.new(download).with_lock do
              download.unlink
            end
          rescue OperationInProgressError
            # Skip incomplete downloads which are still in progress.
            next
          end
        elsif download.directory?
          FileUtils.rm_rf download
        else
          download.unlink
        end
      end
    end

    def cleanup_cache(entries = nil)
      entries ||= cache_files

      entries.each do |entry|
        path = entry[:path]
        next if path == PERIODIC_CLEAN_FILE

        FileUtils.chmod_R 0755, path if self.class.go_cache_directory?(path) && !dry_run?
        next cleanup_path(path) { path.unlink } if self.class.incomplete?(path)
        next cleanup_path(path) { FileUtils.rm_rf path } if self.class.nested_cache?(path)

        if self.class.prune?(path, days)
          if path.file? || path.symlink?
            cleanup_path(path) { path.unlink }
          elsif path.directory? && path.to_s.include?("--")
            cleanup_path(path) { FileUtils.rm_rf path }
          end
          next
        end

        # If we've specified --prune don't do the (expensive) .stale? check.
        cleanup_path(path) { path.unlink } if !prune? && self.class.stale?(entry, scrub: scrub?)
      end

      cleanup_unreferenced_downloads
    end

    def cleanup_path(path)
      return unless path.exist?
      return unless @cleaned_up_paths.add?(path)

      @disk_cleanup_size += path.disk_usage

      if dry_run?
        puts "Would remove: #{path} (#{path.abv})"
      else
        puts "Removing: #{path}... (#{path.abv})"
        yield
      end
    end

    def cleanup_lockfiles(*lockfiles)
      return if dry_run?

      lockfiles = HOMEBREW_LOCKS.children.select(&:file?) if lockfiles.empty? && HOMEBREW_LOCKS.directory?

      lockfiles.each do |file|
        next unless file.readable?
        next unless file.open(File::RDWR).flock(File::LOCK_EX | File::LOCK_NB)

        begin
          file.unlink
        ensure
          file.open(File::RDWR).flock(File::LOCK_UN) if file.exist?
        end
      end
    end

    def cleanup_portable_ruby
      vendor_dir = HOMEBREW_LIBRARY/"Homebrew/vendor"
      portable_ruby_latest_version = (vendor_dir/"portable-ruby-version").read.chomp

      portable_rubies_to_remove = []
      Pathname.glob(vendor_dir/"portable-ruby/*.*").select(&:directory?).each do |path|
        next if !use_system_ruby? && portable_ruby_latest_version == path.basename.to_s

        portable_rubies_to_remove << path
      end

      return if portable_rubies_to_remove.empty?

      bundler_paths = (vendor_dir/"bundle/ruby").children.select do |child|
        basename = child.basename.to_s

        next false if basename == ".homebrew_gem_groups"
        next true unless child.directory?

        [
          "#{Version.new(portable_ruby_latest_version).major_minor}.0",
          RbConfig::CONFIG["ruby_version"],
        ].uniq.exclude?(basename)
      end

      bundler_paths.each do |bundler_path|
        if dry_run?
          puts Utils.popen_read("git", "-C", HOMEBREW_REPOSITORY, "clean", "-nx", bundler_path).chomp
        else
          puts Utils.popen_read("git", "-C", HOMEBREW_REPOSITORY, "clean", "-ffqx", bundler_path).chomp
        end
      end

      portable_rubies_to_remove.each do |portable_ruby|
        cleanup_path(portable_ruby) { FileUtils.rm_r(portable_ruby) }
      end
    end

    def use_system_ruby?
      false
    end

    def cleanup_bootsnap
      bootsnap = cache/"bootsnap"
      return unless bootsnap.directory?

      bootsnap.each_child do |subdir|
        cleanup_path(subdir) { FileUtils.rm_r(subdir) } if subdir.basename.to_s != Homebrew.bootsnap_key
      end
    end

    def cleanup_cache_db(rack = nil)
      FileUtils.rm_rf [
        cache/"desc_cache.json",
        cache/"linkage.db",
        cache/"linkage.db.db",
      ]

      CacheStoreDatabase.use(:linkage) do |db|
        break unless db.created?

        db.each_key do |keg|
          next if rack.present? && !keg.start_with?("#{rack}/")
          next if File.directory?(keg)

          LinkageCacheStore.new(keg, db).delete!
        end
      end
    end

    def rm_ds_store(dirs = nil)
      dirs ||= Keg.must_exist_directories + [
        HOMEBREW_PREFIX/"Caskroom",
      ]
      dirs.select(&:directory?)
          .flat_map { |d| Pathname.glob("#{d}/**/.DS_Store") }
          .each do |dir|
            dir.unlink
          rescue Errno::EACCES
            # don't care if we can't delete a .DS_Store
            nil
          end
    end

    def cleanup_python_site_packages
      pyc_files = Hash.new { |h, k| h[k] = [] }
      seen_non_pyc_file = Hash.new { |h, k| h[k] = false }
      unused_pyc_files = []

      HOMEBREW_PREFIX.glob("lib/python*/site-packages").each do |site_packages|
        site_packages.each_child do |child|
          next unless child.directory?
          # TODO: Work out a sensible way to clean up `pip`'s, `setuptools`' and `wheel`'s
          #       `{dist,site}-info` directories. Alternatively, consider always removing
          #       all `-info` directories, because we may not be making use of them.
          next if child.basename.to_s.end_with?("-info")

          # Clean up old *.pyc files in the top-level __pycache__.
          if child.basename.to_s == "__pycache__"
            child.find do |path|
              next if path.extname != ".pyc"
              next unless self.class.prune?(path, days)

              unused_pyc_files << path
            end

            next
          end

          # Look for directories that contain only *.pyc files.
          child.find do |path|
            next if path.directory?

            if path.extname == ".pyc"
              pyc_files[child] << path
            else
              seen_non_pyc_file[child] = true
              break
            end
          end
        end
      end

      unused_pyc_files += pyc_files.reject { |k,| seen_non_pyc_file[k] }
                                   .values
                                   .flatten
      return if unused_pyc_files.blank?

      unused_pyc_files.each do |pyc|
        cleanup_path(pyc) { pyc.unlink }
      end
    end

    def prune_prefix_symlinks_and_directories
      ObserverPathnameExtension.reset_counts!

      dirs = []
      children_count = {}

      Keg.must_exist_subdirectories.each do |dir|
        next unless dir.directory?

        dir.find do |path|
          path.extend(ObserverPathnameExtension)
          if path.symlink?
            unless path.resolved_path_exists?
              path.uninstall_info if path.to_s.match?(Keg::INFOFILE_RX) && !dry_run?

              if dry_run?
                puts "Would remove (broken link): #{path}"
                children_count[path.dirname] -= 1 if children_count.key?(path.dirname)
              else
                path.unlink
              end
            end
          elsif path.directory? && Keg.must_exist_subdirectories.exclude?(path)
            dirs << path
            children_count[path] = path.children.length if dry_run?
          end
        end
      end

      dirs.reverse_each do |d|
        if !dry_run?
          d.rmdir_if_possible
        elsif children_count[d].zero?
          puts "Would remove (empty directory): #{d}"
          children_count[d.dirname] -= 1 if children_count.key?(d.dirname)
        end
      end

      require "cask/caskroom"
      if Cask::Caskroom.path.directory?
        Cask::Caskroom.path.each_child do |path|
          path.extend(ObserverPathnameExtension)
          next if !path.symlink? || path.resolved_path_exists?

          if dry_run?
            puts "Would remove (broken link): #{path}"
          else
            path.unlink
          end
        end
      end

      return if dry_run?

      return if ObserverPathnameExtension.total.zero?

      n, d = ObserverPathnameExtension.counts
      print "Pruned #{n} symbolic links "
      print "and #{d} directories " if d.positive?
      puts "from #{HOMEBREW_PREFIX}"
    end

    def self.autoremove(dry_run: false)
      require "utils/autoremove"
      require "cask/caskroom"

      # If this runs after install, uninstall, reinstall or upgrade,
      # the cache of installed formulae may no longer be valid.
      Formula.clear_cache unless dry_run

      formulae = Formula.installed
      # Remove formulae listed in HOMEBREW_NO_CLEANUP_FORMULAE and their dependencies.
      if Homebrew::EnvConfig.no_cleanup_formulae.present?
        formulae -= formulae.select { skip_clean_formula?(_1) }
                            .flat_map { |f| [f, *f.runtime_formula_dependencies] }
      end
      casks = Cask::Caskroom.casks

      removable_formulae = Utils::Autoremove.removable_formulae(formulae, casks)

      return if removable_formulae.blank?

      formulae_names = removable_formulae.map(&:full_name).sort

      verb = dry_run ? "Would autoremove" : "Autoremoving"
      oh1 "#{verb} #{formulae_names.count} unneeded #{Utils.pluralize("formula", formulae_names.count, plural: "e")}:"
      puts formulae_names.join("\n")
      return if dry_run

      require "uninstall"

      kegs_by_rack = removable_formulae.filter_map(&:any_installed_keg).group_by(&:rack)
      Uninstall.uninstall_kegs(kegs_by_rack)

      # The installed formula cache will be invalid after uninstalling.
      Formula.clear_cache
    end
  end
end

require "extend/os/cleanup"
