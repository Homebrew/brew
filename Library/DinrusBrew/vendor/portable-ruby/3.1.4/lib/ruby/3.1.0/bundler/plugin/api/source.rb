# frozen_string_literal: true

module Bundler
  module Plugin
    class API
      # This class provides the base to build source plugins
      # All the method here are required to build a source plugin (except
      # `uri_hash`, `gem_install_dir`; they are helpers).
      #
      # Defaults for methods, where ever possible are provided which is
      # expected to work. But, all source plugins have to override
      # `fetch_gemspec_files` and `install`. Defaults are also not provided for
      # `remote!`, `cache!` and `unlock!`.
      #
      # The defaults shall work for most situations but nevertheless they can
      # be (preferably should be) overridden as per the plugins' needs safely
      # (as long as they behave as expected).
      # On overriding `initialize` you should call super first.
      #
      # If required plugin should override `hash`, `==` and `eql?` methods to be
      # able to match objects representing same sources, but may be created in
      # different situation (like form gemfile and lockfile). The default ones
      # checks only for class and uri, but elaborate source plugins may need
      # more comparisons (e.g. git checking on branch or tag).
      #
      # @!attribute [r] uri
      #   @return [String] the remote specified with `source` block in Gemfile
      #
      # @!attribute [r] options
      #   @return [String] options passed during initialization (either from
      #     lockfile or Gemfile)
      #
      # @!attribute [r] name
      #   @return [String] name that can be used to uniquely identify a source
      #
      # @!attribute [rw] dependency_names
      #   @return [Array<String>] Names of dependencies that the source should
      #     try to resolve. It is not necessary to use this list internally. This
      #     is present to be compatible with `Definition` and is used by
      #     rubygems source.
      module Source
        attr_reader :uri, :options, :name
        attr_accessor :dependency_names

        def initialize(opts)
          @options = opts
          @dependency_names = []
          @uri = opts["uri"]
          @type = opts["type"]
          @name = opts["name"] || "#{@type} at #{@uri}"
        end

        # This is used by the default `spec` method to constructs the
        # Specification objects for the gems and versions that can be installed
        # by this source plugin.
        #
        # Note: If the spec method is overridden, this function is not necessary
        #
        # @return [Array<String>] paths of the gemspec files for gems that can
        #                         be installed
        def fetch_gemspec_files
          []
        end

        # Options to be saved in the lockfile so that the source plugin is able
        # to check out same version of gem later.
        #
        # There options are passed when the source plugin is created from the
        # lock file.
        #
        # @return [Hash]
        def options_to_lock
          {}
        end

        # Install the gem specified by the spec at appropriate path.
        # `install_path` provides a sufficient default, if the source can only
        # satisfy one gem,  but is not binding.
        #
        # @return [String] post installation message (if any)
        def install(spec, opts)
          raise MalformattedPlugin, "Source plugins need to override the install method."
        end

        # It builds extensions, generates bins and installs them for the spec
        # provided.
        #
        # It depends on `spec.loaded_from` to get full_gem_path. The source
        # plugins should set that.
        #
        # It should be called in `install` after the plugin is done placing the
        # gem at correct install location.
        #
        # It also runs Gem hooks `pre_install`, `post_build` and `post_install`
        #
        # Note: Do not override if you don't know what you are doing.
        def post_install(spec, disable_exts = false)
          opts = { :env_shebang => false, :disable_extensions => disable_exts }
          installer = Bundler::Source::Path::Installer.new(spec, opts)
          installer.post_install
        end

        # A default installation path to install a single gem. If the source
        # servers multiple gems, it's not of much use and the source should one
        # of its own.
        def install_path
          @install_path ||=
            begin
              base_name = File.basename(Bundler::URI.parse(uri).normalize.path)

              gem_install_dir.join("#{base_name}-#{uri_hash[0..11]}")
            end
        end

        # Parses the gemspec files to find the specs for the gems that can be
        # satisfied by the source.
        #
        # Few important points to keep in mind:
        #   - If the gems are not installed then it shall return specs for all
        #   the gems it can satisfy
        #   - If gem is installed (that is to be detected by the plugin itself)
        #   then it shall return at least the specs that are installed.
        #   - The `loaded_from` for each of the specs shall be correct (it is
        #   used to find the load path)
        #
        # @return [Bundler::Index] index containing the specs
        def specs
          files = fetch_gemspec_files

          Bundler::Index.build do |index|
            files.each do |file|
              next unless spec = Bundler.load_gemspec(file)
              Bundler.rubygems.set_installed_by_version(spec)

              spec.source = self
              Bundler.rubygems.validate(spec)

              index << spec
            end
          end
        end

        # Set internal representation to fetch the gems/specs locally.
        #
        # When this is called, the source should try to fetch the specs and
        # install from the local system.
        def local!
        end

        # Set internal representation to fetch the gems/specs from remote.
        #
        # When this is called, the source should try to fetch the specs and
        # install from remote path.
        def remote!
        end

        # Set internal representation to fetch the gems/specs from app cache.
        #
        # When this is called, the source should try to fetch the specs and
        # install from the path provided by `app_cache_path`.
        def cached!
        end

        # This is called to update the spec and installation.
        #
        # If the source plugin is loaded from lockfile or otherwise, it shall
        # refresh the cache/specs (e.g. git sources can make a fresh clone).
        def unlock!
        end

        # Name of directory where plugin the is expected to cache the gems when
        # #cache is called.
        #
        # Also this name is matched against the directories in cache for pruning
        #
        # This is used by `app_cache_path`
        def app_cache_dirname
          base_name = File.basename(Bundler::URI.parse(uri).normalize.path)
          "#{base_name}-#{uri_hash}"
        end

        # This method is called while caching to save copy of the gems that the
        # source can resolve to path provided by `app_cache_app`so that they can
        # be reinstalled from the cache without querying the remote (i.e. an
        # alternative to remote)
        #
        # This is stored with the app and source plugins should try to provide
        # specs and install only from this cache when `cached!` is called.
        #
        # This cache is different from the internal caching that can be done
        # at sub paths of `cache_path` (from API). This can be though as caching
        # by bundler.
        def cache(spec, custom_path = nil)
          new_cache_path = app_cache_path(custom_path)

          FileUtils.rm_rf(new_cache_path)
          FileUtils.cp_r(install_path, new_cache_path)
          FileUtils.touch(app_cache_path.join(".bundlecache"))
        end

        # This shall check if two source object represent the same source.
        #
        # The comparison shall take place only on the attribute that can be
        # inferred from the options passed from Gemfile and not on attributes
        # that are used to pin down the gem to specific version (e.g. Git
        # sources should compare on branch and tag but not on commit hash)
        #
        # The sources objects are constructed from Gemfile as well as from
        # lockfile. To converge the sources, it is necessary that they match.
        #
        # The same applies for `eql?` and `hash`
        def ==(other)
          other.is_a?(self.class) && uri == other.uri
        end

        # When overriding `eql?` please preserve the behaviour as mentioned in
        # docstring for `==` method.
        alias_method :eql?, :==

        # When overriding `hash` please preserve the behaviour as mentioned in
        # docstring for `==` method, i.e. two methods equal by above comparison
        # should have same hash.
        def hash
          [self.class, uri].hash
        end

        # A helper method, not necessary if not used internally.
        def installed?
          File.directory?(install_path)
        end

        # The full path where the plugin should cache the gem so that it can be
        # installed latter.
        #
        # Note: Do not override if you don't know what you are doing.
        def app_cache_path(custom_path = nil)
          @app_cache_path ||= Bundler.app_cache(custom_path).join(app_cache_dirname)
        end

        # Used by definition.
        #
        # Note: Do not override if you don't know what you are doing.
        def unmet_deps
          specs.unmet_dependency_names
        end

        # Used by definition.
        #
        # Note: Do not override if you don't know what you are doing.
        def spec_names
          specs.spec_names
        end

        # Used by definition.
        #
        # Note: Do not override if you don't know what you are doing.
        def add_dependency_names(names)
          @dependencies |= Array(names)
        end

        # NOTE: Do not override if you don't know what you are doing.
        def can_lock?(spec)
          spec.source == self
        end

        # Generates the content to be entered into the lockfile.
        # Saves type and remote and also calls to `options_to_lock`.
        #
        # Plugin should use `options_to_lock` to save information in lockfile
        # and not override this.
        #
        # Note: Do not override if you don't know what you are doing.
        def to_lock
          out = String.new("#{LockfileParser::PLUGIN}\n")
          out << "  remote: #{@uri}\n"
          out << "  type: #{@type}\n"
          options_to_lock.each do |opt, value|
            out << "  #{opt}: #{value}\n"
          end
          out << "  specs:\n"
        end

        def to_s
          "plugin source for #{@type} with uri #{@uri}"
        end
        alias_method :identifier, :to_s

        # NOTE: Do not override if you don't know what you are doing.
        def include?(other)
          other == self
        end

        def uri_hash
          SharedHelpers.digest(:SHA1).hexdigest(uri)
        end

        # NOTE: Do not override if you don't know what you are doing.
        def gem_install_dir
          Bundler.install_path
        end

        # It is used to obtain the full_gem_path.
        #
        # spec's loaded_from path is expanded against this to get full_gem_path
        #
        # Note: Do not override if you don't know what you are doing.
        def root
          Bundler.root
        end

        # @private
        # This API on source might not be stable, and for now we expect plugins
        # to download all specs in `#specs`, so we implement the method for
        # compatibility purposes and leave it undocumented (and don't support)
        # overriding it)
        def double_check_for(*); end
      end
    end
  end
end
