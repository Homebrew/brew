# frozen_string_literal: true

require "rubygems/user_interaction"

module Bundler
  class Source
    class Rubygems < Source
      autoload :Remote, File.expand_path("rubygems/remote", __dir__)

      # Use the API when installing less than X gems
      API_REQUEST_LIMIT = 500
      # Ask for X gems per API request
      API_REQUEST_SIZE = 50

      attr_reader :remotes, :caches

      def initialize(options = {})
        @options = options
        @remotes = []
        @dependency_names = []
        @allow_remote = false
        @allow_cached = false
        @allow_local = options["allow_local"] || false
        @caches = [cache_path, *Bundler.rubygems.gem_cache]

        Array(options["remotes"]).reverse_each {|r| add_remote(r) }
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
        return if @allow_cached

        @specs = nil
        @allow_local = true
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
        new(options)
      end

      def to_lock
        out = String.new("GEM\n")
        remotes.reverse_each do |remote|
          out << "  remote: #{suppress_configured_credentials remote}\n"
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

      def specs
        @specs ||= begin
          # remote_specs usually generates a way larger Index than the other
          # sources, and large_idx.use small_idx is way faster than
          # small_idx.use large_idx.
          idx = @allow_remote ? remote_specs.dup : Index.new
          idx.use(cached_specs, :override_dupes) if @allow_cached || @allow_remote
          idx.use(installed_specs, :override_dupes) if @allow_local
          idx
        end
      end

      def install(spec, options = {})
        force = options[:force]
        ensure_builtin_gems_cached = options[:ensure_builtin_gems_cached]

        if ensure_builtin_gems_cached && spec.default_gem? && !cached_path(spec)
          cached_built_in_gem(spec) unless spec.remote
          force = true
        end

        if installed?(spec) && !force
          print_using_message "Using #{version_message(spec)}"
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

        if requires_sudo?
          install_path = Bundler.tmp(spec.full_name)
          bin_path     = install_path.join("bin")
        else
          install_path = rubygems_dir
          bin_path     = Bundler.system_bindir
        end

        Bundler.mkdir_p bin_path, :no_sudo => true unless spec.executables.empty? || Bundler.rubygems.provides?(">= 2.7.5")

        require_relative "../rubygems_gem_installer"

        installer = Bundler::RubyGemsGemInstaller.at(
          path,
          :security_policy     => Bundler.rubygems.security_policies[Bundler.settings["trust-policy"]],
          :install_dir         => install_path.to_s,
          :bin_dir             => bin_path.to_s,
          :ignore_dependencies => true,
          :wrappers            => true,
          :env_shebang         => true,
          :build_args          => options[:build_args],
          :bundler_expected_checksum => spec.respond_to?(:checksum) && spec.checksum,
          :bundler_extension_cache_path => extension_cache_path(spec)
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

        message = "Installing #{version_message(spec, options[:previous_spec])}"
        message += " with native extensions" if spec.extensions.any?
        Bundler.ui.confirm message

        installed_spec = installer.install

        spec.full_gem_path = installed_spec.full_gem_path
        spec.loaded_from = installed_spec.loaded_from

        # SUDO HAX
        if requires_sudo?
          Bundler.rubygems.repository_subdirectories.each do |name|
            src = File.join(install_path, name, "*")
            dst = File.join(rubygems_dir, name)
            if name == "extensions" && Dir.glob(src).any?
              src = File.join(src, "*/*")
              ext_src = Dir.glob(src).first
              ext_src.gsub!(src[0..-6], "")
              dst = File.dirname(File.join(dst, ext_src))
            end
            SharedHelpers.filesystem_access(dst) do |p|
              Bundler.mkdir_p(p)
            end
            Bundler.sudo "cp -R #{src} #{dst}" if Dir[src].any?
          end

          spec.executables.each do |exe|
            SharedHelpers.filesystem_access(Bundler.system_bindir) do |p|
              Bundler.mkdir_p(p)
            end
            Bundler.sudo "cp -R #{install_path}/bin/#{exe} #{Bundler.system_bindir}/"
          end
        end

        spec.post_install_message
      ensure
        Bundler.rm_rf(install_path) if requires_sudo?
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

      def cached_built_in_gem(spec)
        cached_path = cached_path(spec)
        if cached_path.nil?
          remote_spec = remote_specs.search(spec).first
          if remote_spec
            cached_path = fetch_gem(remote_spec)
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
        if @allow_remote && dependency_api_available?
          remote_specs.spec_names
        else
          []
        end
      end

      def unmet_deps
        if @allow_remote && dependency_api_available?
          remote_specs.unmet_dependency_names
        else
          []
        end
      end

      def fetchers
        @fetchers ||= remotes.map do |uri|
          remote = Source::Rubygems::Remote.new(uri)
          Bundler::Fetcher.new(remote)
        end
      end

      def double_check_for(unmet_dependency_names)
        return unless @allow_remote
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

        fetch_names(api_fetchers, unmet_dependency_names, specs, false)
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
        api_fetchers.any?
      end

      protected

      def remote_names
        remotes.map(&:to_s).join(", ")
      end

      def credless_remotes
        if Bundler.settings[:allow_deployment_source_credential_changes]
          remotes.map(&method(:remove_auth))
        else
          remotes.map(&method(:suppress_configured_credentials))
        end
      end

      def remotes_for_spec(spec)
        specs.search_all(spec.name).inject([]) do |uris, s|
          uris << s.remote if s.remote
          uris
        end
      end

      def cached_gem(spec)
        if spec.default_gem?
          cached_built_in_gem(spec)
        else
          cached_path(spec)
        end
      end

      def cached_path(spec)
        global_cache_path = download_cache_path(spec)
        @caches << global_cache_path if global_cache_path

        possibilities = @caches.map {|p| package_path(p, spec) }
        possibilities.find {|p| File.exist?(p) }
      end

      def package_path(cache_path, spec)
        "#{cache_path}/#{spec.file_name}"
      end

      def normalize_uri(uri)
        uri = uri.to_s
        uri = "#{uri}/" unless uri =~ %r{/$}
        require_relative "../vendored_uri"
        uri = Bundler::URI(uri)
        raise ArgumentError, "The source must be an absolute URI. For example:\n" \
          "source 'https://rubygems.org'" if !uri.absolute? || (uri.is_a?(Bundler::URI::HTTP) && uri.host.nil?)
        uri
      end

      def suppress_configured_credentials(remote)
        remote_nouser = remove_auth(remote)
        if remote.userinfo && remote.userinfo == Bundler.settings[remote_nouser]
          remote_nouser
        else
          remote
        end
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
          Bundler.rubygems.all_specs.reverse_each do |spec|
            spec.source = self
            if Bundler.rubygems.spec_missing_extensions?(spec, false)
              Bundler.ui.debug "Source #{self} is ignoring #{spec} because it is missing extensions"
              next
            end
            idx << spec
          end
        end
      end

      def cached_specs
        @cached_specs ||= begin
          idx = @allow_local ? installed_specs.dup : Index.new

          Dir["#{cache_path}/*.gem"].each do |gemfile|
            next if gemfile =~ /^bundler\-[\d\.]+?\.gem/
            s ||= Bundler.rubygems.spec_from_gem(gemfile)
            s.source = self
            idx << s
          end

          idx
        end
      end

      def api_fetchers
        fetchers.select {|f| f.use_api && f.fetchers.first.api_fetcher? }
      end

      def remote_specs
        @remote_specs ||= Index.build do |idx|
          index_fetchers = fetchers - api_fetchers

          # gather lists from non-api sites
          fetch_names(index_fetchers, nil, idx, false)

          # because ensuring we have all the gems we need involves downloading
          # the gemspecs of those gems, if the non-api sites contain more than
          # about 500 gems, we treat all sites as non-api for speed.
          allow_api = idx.size < API_REQUEST_LIMIT && dependency_names.size < API_REQUEST_LIMIT
          Bundler.ui.debug "Need to query more than #{API_REQUEST_LIMIT} gems." \
            " Downloading full index instead..." unless allow_api

          fetch_names(api_fetchers, allow_api && dependency_names, idx, false)
        end
      end

      def fetch_names(fetchers, dependency_names, index, override_dupes)
        fetchers.each do |f|
          if dependency_names
            Bundler.ui.info "Fetching gem metadata from #{URICredentialsFilter.credential_filtered_uri(f.uri)}", Bundler.ui.debug?
            index.use f.specs_with_retry(dependency_names, self), override_dupes
            Bundler.ui.info "" unless Bundler.ui.debug? # new line now that the dots are over
          else
            Bundler.ui.info "Fetching source index from #{URICredentialsFilter.credential_filtered_uri(f.uri)}"
            index.use f.specs_with_retry(nil, self), override_dupes
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

        if requires_sudo?
          download_path = Bundler.tmp(spec.full_name)
          download_cache_path = default_cache_path_for(download_path)
        else
          download_cache_path = cache_path
        end

        SharedHelpers.filesystem_access(download_cache_path) do |p|
          FileUtils.mkdir_p(p)
        end
        download_gem(spec, download_cache_path, previous_spec)

        if requires_sudo?
          SharedHelpers.filesystem_access(cache_path) do |p|
            Bundler.mkdir_p(p)
          end
          Bundler.sudo "mv #{package_path(download_cache_path, spec)} #{gem_path}"
        end

        gem_path
      ensure
        Bundler.rm_rf(download_path) if requires_sudo?
      end

      def installed?(spec)
        installed_specs[spec].any? && !spec.deleted_gem?
      end

      def requires_sudo?
        Bundler.requires_sudo?
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
        Bundler.rubygems.download_gem(spec, uri, download_cache_path)
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
