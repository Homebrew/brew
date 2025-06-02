# frozen_string_literal: true

require_relative "../vendored_fileutils"

module Bundler
  class Source
    class Git < Path
      autoload :GitProxy, File.expand_path("git/git_proxy", __dir__)

      attr_reader :uri, :ref, :branch, :options, :glob, :submodules

      def initialize(options)
        @options = options
        @checksum_store = Checksum::Store.new
        @glob = options["glob"] || DEFAULT_GLOB

        @allow_cached = false
        @allow_remote = false

        # Stringify options that could be set as symbols
        %w[ref branch tag revision].each {|k| options[k] = options[k].to_s if options[k] }

        @uri        = URINormalizer.normalize_suffix(options["uri"] || "", trailing_slash: false)
        @safe_uri   = URICredentialsFilter.credential_filtered_uri(@uri)
        @branch     = options["branch"]
        @ref        = options["ref"] || options["branch"] || options["tag"]
        @submodules = options["submodules"]
        @name       = options["name"]
        @version    = options["version"].to_s.strip.gsub("-", ".pre.")

        @copied     = false
        @local      = false
      end

      def remote!
        return if @allow_remote

        @local_specs = nil
        @allow_remote = true
      end

      def cached!
        return if @allow_cached

        @local_specs = nil
        @allow_cached = true
      end

      def self.from_lock(options)
        new(options.merge("uri" => options.delete("remote")))
      end

      def to_lock
        out = String.new("GIT\n")
        out << "  remote: #{@uri}\n"
        out << "  revision: #{revision}\n"
        %w[ref branch tag submodules].each do |opt|
          out << "  #{opt}: #{options[opt]}\n" if options[opt]
        end
        out << "  glob: #{@glob}\n" unless default_glob?
        out << "  specs:\n"
      end

      def to_gemfile
        specifiers = %w[ref branch tag submodules glob].map do |opt|
          "#{opt}: #{options[opt]}" if options[opt]
        end

        uri_with_specifiers(specifiers)
      end

      def hash
        [self.class, uri, ref, branch, name, glob, submodules].hash
      end

      def eql?(other)
        other.is_a?(Git) && uri == other.uri && ref == other.ref &&
          branch == other.branch && name == other.name &&
          glob == other.glob &&
          submodules == other.submodules
      end

      alias_method :==, :eql?

      def include?(other)
        other.is_a?(Git) && uri == other.uri &&
          name == other.name &&
          glob == other.glob &&
          submodules == other.submodules
      end

      def to_s
        begin
          at = humanized_ref || current_branch

          rev = "at #{at}@#{shortref_for_display(revision)}"
        rescue GitError
          ""
        end

        uri_with_specifiers([rev, glob_for_display])
      end

      def identifier
        uri_with_specifiers([humanized_ref, cached_revision, glob_for_display])
      end

      def uri_with_specifiers(specifiers)
        specifiers.compact!

        suffix =
          if specifiers.any?
            " (#{specifiers.join(", ")})"
          else
            ""
          end

        "#{@safe_uri}#{suffix}"
      end

      def name
        File.basename(@uri, ".git")
      end

      # This is the path which is going to contain a specific
      # checkout of the git repository. When using local git
      # repos, this is set to the local repo.
      def install_path
        @install_path ||= begin
          git_scope = "#{base_name}-#{shortref_for_path(revision)}"

          Bundler.install_path.join(git_scope)
        end
      end

      alias_method :path, :install_path

      def extension_dir_name
        "#{base_name}-#{shortref_for_path(revision)}"
      end

      def unlock!
        git_proxy.revision = nil
        options["revision"] = nil

        @unlocked = true
      end

      def local_override!(path)
        return false if local?

        original_path = path
        path = Pathname.new(path)
        path = path.expand_path(Bundler.root) unless path.relative?

        unless branch || Bundler.settings[:disable_local_branch_check]
          raise GitError, "Cannot use local override for #{name} at #{path} because " \
            ":branch is not specified in Gemfile. Specify a branch or run " \
            "`bundle config unset local.#{override_for(original_path)}` to remove the local override"
        end

        unless path.exist?
          raise GitError, "Cannot use local override for #{name} because #{path} " \
            "does not exist. Run `bundle config unset local.#{override_for(original_path)}` to remove the local override"
        end

        @local = true
        set_paths!(path)

        # Create a new git proxy without the cached revision
        # so the Gemfile.lock always picks up the new revision.
        @git_proxy = GitProxy.new(path, uri, options)

        if current_branch != branch && !Bundler.settings[:disable_local_branch_check]
          raise GitError, "Local override for #{name} at #{path} is using branch " \
            "#{current_branch} but Gemfile specifies #{branch}"
        end

        changed = cached_revision && cached_revision != revision

        if !Bundler.settings[:disable_local_revision_check] && changed && !@unlocked && !git_proxy.contains?(cached_revision)
          raise GitError, "The Gemfile lock is pointing to revision #{shortref_for_display(cached_revision)} " \
            "but the current branch in your local override for #{name} does not contain such commit. " \
            "Please make sure your branch is up to date."
        end

        changed
      end

      def specs(*)
        set_up_app_cache!(app_cache_path) if use_app_cache?

        if requires_checkout? && !@copied
          FileUtils.rm_rf(app_cache_path) if use_app_cache? && git_proxy.not_a_repository?

          fetch
          checkout
        end

        local_specs
      end

      def install(spec, options = {})
        return if Bundler.settings[:no_install]
        force = options[:force]

        print_using_message "Using #{version_message(spec, options[:previous_spec])} from #{self}"

        if (requires_checkout? && !@copied) || force
          checkout
        end

        generate_bin_options = { disable_extensions: !spec.missing_extensions?, build_args: options[:build_args] }
        generate_bin(spec, generate_bin_options)

        requires_checkout? ? spec.post_install_message : nil
      end

      def cache(spec, custom_path = nil)
        app_cache_path = app_cache_path(custom_path)
        return unless Bundler.feature_flag.cache_all?
        return if install_path == app_cache_path
        return if cache_path == app_cache_path
        cached!
        FileUtils.rm_rf(app_cache_path)
        git_proxy.checkout if requires_checkout?
        FileUtils.cp_r("#{cache_path}/.", app_cache_path)
        FileUtils.touch(app_cache_path.join(".bundlecache"))
        FileUtils.rm_rf(Dir.glob(app_cache_path.join("hooks/*.sample")))
      end

      def load_spec_files
        super
      rescue PathError => e
        Bundler.ui.trace e
        raise GitError, "#{self} is not yet checked out. Run `bundle install` first."
      end

      # This is the path which is going to contain a cache
      # of the git repository. When using the same git repository
      # across different projects, this cache will be shared.
      # When using local git repos, this is set to the local repo.
      def cache_path
        @cache_path ||= if Bundler.feature_flag.global_gem_cache?
          Bundler.user_cache
        else
          Bundler.bundle_path.join("cache", "bundler")
        end.join("git", git_scope)
      end

      def app_cache_dirname
        "#{base_name}-#{shortref_for_path(cached_revision || revision)}"
      end

      def revision
        git_proxy.revision
      end

      def current_branch
        git_proxy.current_branch
      end

      def allow_git_ops?
        @allow_remote || @allow_cached
      end

      def local?
        @local
      end

      private

      def checkout
        Bundler.ui.debug "  * Checking out revision: #{ref}"
        git_proxy.copy_to(install_path, submodules)
        serialize_gemspecs_in(install_path)
        @copied = true
      end

      def humanized_ref
        if local?
          path
        elsif user_ref = options["ref"]
          if /\A[a-z0-9]{4,}\z/i.match?(ref)
            shortref_for_display(user_ref)
          else
            user_ref
          end
        elsif ref
          ref
        end
      end

      def serialize_gemspecs_in(destination)
        destination = destination.expand_path(Bundler.root) if destination.relative?
        Dir["#{destination}/#{@glob}"].each do |spec_path|
          # Evaluate gemspecs and cache the result. Gemspecs
          # in git might require git or other dependencies.
          # The gemspecs we cache should already be evaluated.
          spec = Bundler.load_gemspec(spec_path)
          next unless spec
          spec.installed_by_version = Gem::VERSION
          Bundler.rubygems.validate(spec)
          File.open(spec_path, "wb") {|file| file.write(spec.to_ruby) }
        end
      end

      def set_paths!(path)
        set_cache_path!(path)
        set_install_path!(path)
      end

      def set_cache_path!(path)
        @git_proxy = nil
        @cache_path = path
      end

      def set_install_path!(path)
        @local_specs = nil
        @install_path = path
      end

      def set_up_app_cache!(path)
        FileUtils.mkdir_p(path.join("refs"))
        set_cache_path!(path)
      end

      def has_app_cache?
        cached_revision && super
      end

      def use_app_cache?
        has_app_cache? && !local?
      end

      def requires_checkout?
        allow_git_ops? && !local? && !cached_revision_checked_out?
      end

      def cached_revision_checked_out?
        cached_revision && cached_revision == revision && install_path.exist?
      end

      def base_name
        File.basename(uri.sub(%r{^(\w+://)?([^/:]+:)?(//\w*/)?(\w*/)*}, ""), ".git")
      end

      def shortref_for_display(ref)
        ref[0..6]
      end

      def shortref_for_path(ref)
        ref[0..11]
      end

      def glob_for_display
        default_glob? ? nil : "glob: #{@glob}"
      end

      def default_glob?
        @glob == DEFAULT_GLOB
      end

      def uri_hash
        if %r{^\w+://(\w+@)?}.match?(uri)
          # Downcase the domain component of the URI
          # and strip off a trailing slash, if one is present
          input = Gem::URI.parse(uri).normalize.to_s.sub(%r{/$}, "")
        else
          # If there is no URI scheme, assume it is an ssh/git URI
          input = uri
        end
        # We use SHA1 here for historical reason and to preserve backward compatibility.
        # But a transition to a simpler mangling algorithm would be welcome.
        Bundler::Digest.sha1(input)
      end

      def cached_revision
        options["revision"]
      end

      def cached?
        cache_path.exist?
      end

      def git_proxy
        @git_proxy ||= GitProxy.new(cache_path, uri, options, cached_revision, self)
      end

      def fetch
        git_proxy.checkout
      rescue GitError => e
        raise unless Bundler.feature_flag.allow_offline_install?
        Bundler.ui.warn "Using cached git data because of network errors:\n#{e}"
      end

      # no-op, since we validate when re-serializing the gemspec
      def validate_spec(_spec); end

      def load_gemspec(file)
        dirname = Pathname.new(file).dirname
        SharedHelpers.chdir(dirname.to_s) do
          stub = Gem::StubSpecification.gemspec_stub(file, install_path.parent, install_path.parent)
          stub.full_gem_path = dirname.expand_path(root).to_s
          StubSpecification.from_stub(stub)
        end
      end

      def git_scope
        "#{base_name}-#{uri_hash}"
      end

      def extension_cache_slug(_)
        extension_dir_name
      end

      def override_for(path)
        Bundler.settings.local_overrides.key(path)
      end
    end
  end
end
