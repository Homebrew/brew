# frozen_string_literal: true

module Bundler
  class Source
    class Path < Source
      autoload :Installer, File.expand_path("path/installer", __dir__)

      attr_reader :path, :options, :root_path, :original_path
      attr_writer :name
      attr_accessor :version

      protected :original_path

      DEFAULT_GLOB = "{,*,*/*}.gemspec"

      def initialize(options)
        @checksum_store = Checksum::Store.new
        @options = options.dup
        @glob = options["glob"] || DEFAULT_GLOB

        @root_path = options["root_path"] || root

        if options["path"]
          @path = Pathname.new(options["path"])
          expanded_path = expand(@path)
          @path = if @path.relative?
            expanded_path.relative_path_from(root_path.expand_path)
          else
            expanded_path
          end
        end

        @name    = options["name"]
        @version = options["version"]

        # Stores the original path. If at any point we move to the
        # cached directory, we still have the original path to copy from.
        @original_path = @path
      end

      def self.from_lock(options)
        new(options.merge("path" => options.delete("remote")))
      end

      def to_lock
        out = String.new("PATH\n")
        out << "  remote: #{lockfile_path}\n"
        out << "  glob: #{@glob}\n" unless @glob == DEFAULT_GLOB
        out << "  specs:\n"
      end

      def to_s
        "source at `#{@path}`"
      end

      alias_method :to_gemfile, :path

      def hash
        [self.class, expanded_path, version].hash
      end

      def eql?(other)
        return unless other.class == self.class
        expanded_original_path == other.expanded_original_path &&
          version == other.version
      end

      alias_method :==, :eql?

      def name
        File.basename(expanded_path.to_s)
      end

      def install(spec, options = {})
        using_message = "Using #{version_message(spec, options[:previous_spec])} from #{self}"
        using_message += " and installing its executables" unless spec.executables.empty?
        print_using_message using_message
        generate_bin(spec, disable_extensions: true)
        nil # no post-install message
      end

      def cache(spec, custom_path = nil)
        app_cache_path = app_cache_path(custom_path)
        return unless Bundler.feature_flag.cache_all?
        return if expand(@original_path).to_s.index(root_path.to_s + "/") == 0

        unless @original_path.exist?
          raise GemNotFound, "Can't cache gem #{version_message(spec)} because #{self} is missing!"
        end

        FileUtils.rm_rf(app_cache_path)
        FileUtils.cp_r("#{@original_path}/.", app_cache_path)
        FileUtils.touch(app_cache_path.join(".bundlecache"))
      end

      def local_specs(*)
        @local_specs ||= load_spec_files
      end

      def specs
        if has_app_cache?
          @path = app_cache_path
          @expanded_path = nil # Invalidate
        end
        local_specs
      end

      def app_cache_dirname
        name
      end

      def root
        Bundler.root
      end

      def expanded_original_path
        @expanded_original_path ||= expand(original_path)
      end

      private

      def expanded_path
        @expanded_path ||= expand(path)
      end

      def expand(somepath)
        if Bundler.current_ruby.jruby? # TODO: Unify when https://github.com/rubygems/bundler/issues/7598 fixed upstream and all supported jrubies include the fix
          somepath.expand_path(root_path).expand_path
        else
          somepath.expand_path(root_path)
        end
      rescue ArgumentError => e
        Bundler.ui.debug(e)
        raise PathError, "There was an error while trying to use the path " \
          "`#{somepath}`.\nThe error message was: #{e.message}."
      end

      def lockfile_path
        return relative_path(original_path) if original_path.absolute?
        expand(original_path).relative_path_from(root)
      end

      def app_cache_path(custom_path = nil)
        @app_cache_path ||= Bundler.app_cache(custom_path).join(app_cache_dirname)
      end

      def has_app_cache?
        SharedHelpers.in_bundle? && app_cache_path.exist?
      end

      def load_gemspec(file)
        return unless spec = Bundler.load_gemspec(file)
        spec.installed_by_version = Gem::VERSION
        spec
      end

      def validate_spec(spec)
        Bundler.rubygems.validate(spec)
      end

      def load_spec_files
        index = Index.new

        if File.directory?(expanded_path)
          # We sort depth-first since `<<` will override the earlier-found specs
          Gem::Util.glob_files_in_dir(@glob, expanded_path).sort_by {|p| -p.split(File::SEPARATOR).size }.each do |file|
            next unless spec = load_gemspec(file)
            spec.source = self

            # Validation causes extension_dir to be calculated, which depends
            # on #source, so we validate here instead of load_gemspec
            validate_spec(spec)
            index << spec
          end

          if index.empty? && @name && @version
            index << Gem::Specification.new do |s|
              s.name     = @name
              s.source   = self
              s.version  = Gem::Version.new(@version)
              s.platform = Gem::Platform::RUBY
              s.summary  = "Fake gemspec for #{@name}"
              s.relative_loaded_from = "#{@name}.gemspec"
              s.authors = ["no one"]
              if expanded_path.join("bin").exist?
                executables = expanded_path.join("bin").children
                executables.reject! {|p| File.directory?(p) }
                s.executables = executables.map {|c| c.basename.to_s }
              end
            end
          end
        else
          message = String.new("The path `#{expanded_path}` ")
          message << if File.exist?(expanded_path)
            "is not a directory."
          else
            "does not exist."
          end
          raise PathError, message
        end

        index
      end

      def relative_path(path = self.path)
        if path.to_s.start_with?(root_path.to_s)
          return path.relative_path_from(root_path)
        end
        path
      end

      def generate_bin(spec, options = {})
        gem_dir = Pathname.new(spec.full_gem_path)

        # Some gem authors put absolute paths in their gemspec
        # and we have to save them from themselves
        spec.files = spec.files.map do |path|
          next path unless /\A#{Pathname::SEPARATOR_PAT}/o.match?(path)
          next if File.directory?(path)
          begin
            Pathname.new(path).relative_path_from(gem_dir).to_s
          rescue ArgumentError
            path
          end
        end.compact

        installer = Path::Installer.new(
          spec,
          env_shebang: false,
          disable_extensions: options[:disable_extensions],
          build_args: options[:build_args],
          bundler_extension_cache_path: extension_cache_path(spec)
        )
        installer.post_install
      rescue Gem::InvalidSpecificationException => e
        Bundler.ui.warn "\n#{spec.name} at #{spec.full_gem_path} did not have a valid gemspec.\n" \
                        "This prevents bundler from installing bins or native extensions, but " \
                        "that may not affect its functionality."

        if !spec.extensions.empty? && !spec.email.empty?
          Bundler.ui.warn "If you need to use this package without installing it from a gem " \
                          "repository, please contact #{spec.email} and ask them " \
                          "to modify their .gemspec so it can work with `gem build`."
        end

        Bundler.ui.warn "The validation message from RubyGems was:\n  #{e.message}"
      end
    end
  end
end
