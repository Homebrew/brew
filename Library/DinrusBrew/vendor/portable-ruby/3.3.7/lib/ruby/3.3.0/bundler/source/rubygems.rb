# frozen_string_literal: true

require "rubygems/user_interaction"

module Bundler
  class Source
    class Rubygems < Source
      autoload :Remote, File.expand_path("rubygems/remote", __dir__)

      # Ask for X gems per API request
      API_REQUEST_SIZE = 50

      attr_accessor :remotes

      def initialize(options = {})
        @options = options
        @remotes = []
        @dependency_names = []
        @allow_remote = false
        @allow_cached = false
        @allow_local = options["allow_local"] || false
        @checksum_store = Checksum::Store.new

        Array(options["remotes"]).reverse_each {|r| add_remote(r) }

        @lockfile_remotes = @remotes if options["from_lockfile"]
      end

      def caches
        @caches ||= [cache_path, *Bundler.rubygems.gem_cache]
      end

      def local_only!
        @specs = nil
        @allow_local = true
        @allow_cached = false
        @allow_remote = false
      end

      def local!
        return if @allow_local

        @specs = nil
        @allow_local = true
      end

      def remote!
        return if @allow_remote

        @specs = nil
        @allow_remote = true
      end

      def cached!
        return unless File.exist?(cache_path)

        return if @allow_cached

        @specs = nil
        @allow_cached = true
      end

      def hash
        @remotes.hash
      end

      def eql?(other)
        other.is_a?(Rubygems) && other.credless_remotes == credless_remotes
      end

      alias_method :==, :eql?

      def include?(o)
        o.is_a?(Rubygems) && (o.credless_remotes - credless_remotes).empty?
      end

      def multiple_remotes?
        @remotes.size > 1
      end

      def no_remotes?
        @remotes.size == 0
      end

      def can_lock?(spec)
        return super unless multiple_remotes?
        include?(spec.source)
      end

      def options
        { "remotes" => @remotes.map(&:to_s) }
      end

      def self.from_lock(options)
        options["remotes"] = Array(options.delete("remote")).reverse
        new(options.merge("from_lockfile" => true))
      end

      def to_lock
        out = String.new("GEM\n")
        lockfile_remotes.reverse_each do |remote|
          out << "  remote: #{remote}\n"
        end
        out << "  specs:\n"
      end

      def to_s
        if remotes.empty?
          "locally installed gems"
        elsif @allow_remote && @allow_cached && @allow_local
          "rubygems repository #{remote_names}, cached gems or installed locally"
        elsif @allow_remote && @allow_local
          "rubygems repository #{remote_names} or installed locally"
        elsif @allow_remote
          "rubygems repository #{remote_names}"
        elsif @allow_cached && @allow_local
          "cached gems or installed locally"
        else
          "locally installed gems"
        end
      end

      def identifier
        if remotes.empty?
          "locally installed gems"
        else
          "rubygems repository #{remote_names}"
        end
      end
      alias_method :name, :identifier
      alias_method :to_gemfile, :identifier

      def specs
        @specs ||= begin
          # remote_specs usually generates a way larger Index than the other
          # sources, and large_idx.merge! small_idx is way faster than
          # small_idx.merge! large_idx.
          index = @allow_remote ? remote_specs.dup : Index.new
          index.merge!(cached_specs) if @allow_cached
          index.merge!(installed_specs) if @allow_local

          # complete with default specs, only if not already available in the
          # index through remote, cached, or installed specs
          index.use(default_specs) if @allow_local

          index
        end
      end

      def install(spec, options = {})
        if (spec.default_gem? && !cached_built_in_gem(spec, local: options[:local])) || (installed?(spec) && !options[:force])
          print_using_message "Using #{version_message(spec, options[:previous_spec])}"
          return nil # no post-install message
        end

        if spec.remote
          # Check for this spec from other sources
          uris = [spec.remote, *remotes_for_spec(spec)].map(&:anonymized_uri).uniq
          Installer.ambiguous_gems << [spec.name, *uris] if uris.length > 1
        end

        path = fetch_gem_if_possible(spec, options[:previous_spec])
        raise GemNotFound, "Could not find #{spec.file_name} for installation" unless path

        return if Bundler.settings[:no_install]

        install_path = rubygems_dir
        bin_path     = Bundler.system_bindir

        require_relative "../rubygems_gem_installer"

        installer = Bundler::RubyGemsGemInstaller.at(
          path,
          security_policy: Bundler.rubygems.security_policies[Bundler.settings["trust-policy"]],
          install_dir: install_path.to_s,
          bin_dir: bin_path.to_s,
          ignore_dependencies: true,
          wrappers: true,
          env_shebang: true,
          build_args: options[:build_args],
          bundler_extension_cache_path: extension_cache_path(spec)
        )

        if spec.remote
          s = begin
            installer.spec
          rescue Gem::Package::FormatError
            Bundler.rm_rf(path)
            raise
          rescue Gem::Security::Exception => e
            raise SecurityError,
             "The gem #{File.basename(path, ".gem")} can't be installed because " \
             "the security policy didn't allow it, with the message: #{e.message}"
          end

          spec.__swap__(s)
        end

        spec.source.checksum_store.register(spec, installer.gem_checksum)

        message = "Installing #{version_message(spec, options[:previous_spec])}"
        message += " with native extensions" if spec.extensions.any?
        Bundler.ui.confirm message

        installed_spec = installer.install

        spec.full_gem_path = installed_spec.full_gem_path
        spec.loaded_from = installed_spec.loaded_from
        spec.base_dir = installed_spec.base_dir

        spec.post_install_message
      end

      def cache(spec, custom_path = nil)
        cached_path = Bundler.settings[:cache_all_platforms] ? fetch_gem_if_possible(spec) : cached_gem(spec)
        raise GemNotFound, "Missing gem file '#{spec.file_name}'." unless cached_path
        return if File.dirname(cached_path) == Bundler.app_cache.to_s
        Bundler.ui.info "  * #{File.basename(cached_path)}"
        FileUtils.cp(cached_path, Bundler.app_cache(custom_path))
      rescue Errno::EACCES => e
        Bundler.ui.debug(e)
        raise InstallError, e.message
      end

      def cached_built_in_gem(spec, local: false)
        cached_path = cached_gem(spec)
        if cached_path.nil? && !local
          remote_spec = remote_specs.search(spec).first
          if remote_spec
            cached_path = fetch_gem(remote_spec)
            spec.remote = remote_spec.remote
          else
            Bundler.ui.warn "#{spec.full_name} is built in to Ruby, and can't be cached because your Gemfile doesn't have any sources that contain it."
          end
        end
        cached_path
      end

      def add_remote(source)
        uri = normalize_uri(source)
        @remotes.unshift(uri) unless @remotes.include?(uri)
      end

      def spec_names
        if dependency_api_available?
          remote_specs.spec_names
        else
          []
        end
      end

      def unmet_deps
        if dependency_api_available?
          remote_specs.unmet_dependency_names
        else
          []
        end
      end

      def remote_fetchers
        @remote_fetchers ||= remotes.to_h do |uri|
          remote = Source::Rubygems::Remote.new(uri)
          [remote, Bundler::Fetcher.new(remote)]
        end.freeze
      end

      def fetchers
        @fetchers ||= remote_fetchers.values.freeze
      end

      def double_check_for(unmet_dependency_names)
        return unless dependency_api_available?

        unmet_dependency_names = unmet_dependency_names.call
        unless unmet_dependency_names.nil?
          if api_fetchers.size <= 1
            # can't do this when there are multiple fetchers because then we might not fetch from _all_
            # of them
            unmet_dependency_names -= remote_specs.spec_names # avoid re-fetching things we've already gotten
          end
          return if unmet_dependency_names.empty?
        end

        Bundler.ui.debug "Double checking for #{unmet_dependency_names || "all specs (due to the size of the request)"} in #{self}"

        fetch_names(api_fetchers, unmet_dependency_names, remote_specs)

        specs.use remote_specs
      end

      def dependency_names_to_double_check
        names = []
        remote_specs.each do |spec|
          case spec
          when EndpointSpecification, Gem::Specification, StubSpecification, LazySpecification
            names.concat(spec.runtime_dependencies.map(&:name))
          when RemoteSpecification # from the full index
            return nil
          else
            raise "unhandled spec type (#{spec.inspect})"
          end
        end
        names
      end

      def dependency_api_available?
        @allow_remote && api_fetchers.any?
      end

      protected

      def remote_names
        remotes.map(&:to_s).join(", ")
      end

      def credless_remotes
        remotes.map(&method(:remove_auth))
      end

      def remotes_for_spec(spec)
        specs.search_all(spec.name).inject([]) do |uris, s|
          uris << s.remote if s.remote
          uris
        end
      end

      def cached_gem(spec)
        global_cache_path = download_cache_path(spec)
        caches << global_cache_path if global_cache_path

        possibilities = caches.map {|p| package_path(p, spec) }
        possibilities.find {|p| File.exist?(p) }
      end

      def package_path(cache_path, spec)
        "#{cache_path}/#{spec.file_name}"
      end

      def normalize_uri(uri)
        uri = URINormalizer.normalize_suffix(uri.to_s)
        require_relative "../vendored_uri"
        uri = Gem::URI(uri)
        raise ArgumentError, "The source must be an absolute URI. For example:\n" \
          "source 'https://rubygems.org'" if !uri.absolute? || (uri.is_a?(Gem::URI::HTTP) && uri.host.nil?)
        uri
      end

      def remove_auth(remote)
        if remote.user || remote.password
          remote.dup.tap {|uri| uri.user = uri.password = nil }.to_s
        else
          remote.to_s
        end
      end

      def installed_specs
        @installed_specs ||= Index.build do |idx|
          Bundler.rubygems.installed_specs.reverse_each do |spec|
            spec.source = self
            next if spec.ignored?
            idx << spec
          end
        end
      end

      def default_specs
        @default_specs ||= Index.build do |idx|
          Bundler.rubygems.default_specs.each do |spec|
            spec.source = self
            idx << spec
          end
        end
      end

      def cached_specs
        @cached_specs ||= begin
          idx = Index.new

          Dir["#{cache_path}/*.gem"].each do |gemfile|
            s ||= Bundler.rubygems.spec_from_gem(gemfile)
            s.source = self
            idx << s
          end

          idx
        end
      end

      def api_fetchers
        fetchers.select(&:api_fetcher?)
      end

      def remote_specs
        @remote_specs ||= Index.build do |idx|
          index_fetchers = fetchers - api_fetchers

          if index_fetchers.empty?
            fetch_names(api_fetchers, dependency_names, idx)
          else
            fetch_names(fetchers, nil, idx)
          end
        end
      end

      def fetch_names(fetchers, dependency_names, index)
        fetchers.each do |f|
          if dependency_names
            Bundler.ui.info "Fetching gem metadata from #{URICredentialsFilter.credential_filtered_uri(f.uri)}", Bundler.ui.debug?
            index.use f.specs_with_retry(dependency_names, self)
            Bundler.ui.info "" unless Bundler.ui.debug? # new line now that the dots are over
          else
            Bundler.ui.info "Fetching source index from #{URICredentialsFilter.credential_filtered_uri(f.uri)}"
            index.use f.specs_with_retry(nil, self)
          end
        end
      end

      def fetch_gem_if_possible(spec, previous_spec = nil)
        if spec.remote
          fetch_gem(spec, previous_spec)
        else
          cached_gem(spec)
        end
      end

      def fetch_gem(spec, previous_spec = nil)
        spec.fetch_platform

        cache_path = download_cache_path(spec) || default_cache_path_for(rubygems_dir)
        gem_path = package_path(cache_path, spec)
        return gem_path if File.exist?(gem_path)

        SharedHelpers.filesystem_access(cache_path) do |p|
          FileUtils.mkdir_p(p)
        end
        download_gem(spec, cache_path, previous_spec)

        gem_path
      end

      def installed?(spec)
        installed_specs[spec].any? && !spec.deleted_gem?
      end

      def rubygems_dir
        Bundler.bundle_path
      end

      def default_cache_path_for(dir)
        "#{dir}/cache"
      end

      def cache_path
        Bundler.app_cache
      end

      private

      def lockfile_remotes
        @lockfile_remotes || credless_remotes
      end

      # Checks if the requested spec exists in the global cache. If it does,
      # we copy it to the download path, and if it does not, we download it.
      #
      # @param  [Specification] spec
      #         the spec we want to download or retrieve from the cache.
      #
      # @param  [String] download_cache_path
      #         the local directory the .gem will end up in.
      #
      # @param  [Specification] previous_spec
      #         the spec previously locked
      #
      def download_gem(spec, download_cache_path, previous_spec = nil)
        uri = spec.remote.uri
        Bundler.ui.confirm("Fetching #{version_message(spec, previous_spec)}")
        gem_remote_fetcher = remote_fetchers.fetch(spec.remote).gem_remote_fetcher
        Bundler.rubygems.download_gem(spec, uri, download_cache_path, gem_remote_fetcher)
      end

      # Returns the global cache path of the calling Rubygems::Source object.
      #
      # Note that the Source determines the path's subdirectory. We use this
      # subdirectory in the global cache path so that gems with the same name
      # -- and possibly different versions -- from different sources are saved
      # to their respective subdirectories and do not override one another.
      #
      # @param  [Gem::Specification] specification
      #
      # @return [Pathname] The global cache path.
      #
      def download_cache_path(spec)
        return unless Bundler.feature_flag.global_gem_cache?
        return unless remote = spec.remote
        return unless cache_slug = remote.cache_slug

        Bundler.user_cache.join("gems", cache_slug)
      end

      def extension_cache_slug(spec)
        return unless remote = spec.remote
        remote.cache_slug
      end
    end
  end
end
