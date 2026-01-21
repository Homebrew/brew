# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cask/cache"
require "cask/cask"
require "uri"
require "utils/curl"
require "utils/output"
require "utils/path"
require "extend/hash/keys"
require "api"

module Cask
  # Loads a cask from various sources.
  module CaskLoader
    extend Context
    extend ::Utils::Output::Mixin

    ALLOWED_URL_SCHEMES = %w[file].freeze
    private_constant :ALLOWED_URL_SCHEMES

    module ILoader
      extend T::Helpers
      include ::Utils::Output::Mixin

      interface!

      sig { abstract.params(config: T.nilable(Config)).returns(Cask) }
      def load(config:); end
    end

    # Loads a cask from a string.
    class AbstractContentLoader
      include ILoader
      extend T::Helpers

      abstract!

      sig { returns(String) }
      attr_reader :content

      sig { returns(T.nilable(Tap)) }
      attr_reader :tap

      private

      sig {
        overridable.params(
          header_token: String,
          options:      T.untyped,
          block:        T.nilable(T.proc.bind(DSL).void),
        ).returns(Cask)
      }
      def cask(header_token, **options, &block)
        Cask.new(header_token, source: content, tap:, **options, config: @config, &block)
      end
    end

    # Loads a cask from a string.
    class FromContentLoader < AbstractContentLoader
      sig {
        params(ref: T.any(Pathname, String, Cask, URI::Generic), warn: T::Boolean)
          .returns(T.nilable(T.attached_class))
      }
      def self.try_new(ref, warn: false)
        return if ref.is_a?(Cask)

        content = ref.to_str

        # Cache compiled regex
        @regex ||= begin
          token  = /(?:"[^"]*"|'[^']*')/
          curly  = /\(\s*#{token.source}\s*\)\s*\{.*\}/
          do_end = /\s+#{token.source}\s+do(?:\s*;\s*|\s+).*end/
          /\A\s*cask(?:#{curly.source}|#{do_end.source})\s*\Z/m
        end

        return unless content.match?(@regex)

        new(content)
      end

      sig { params(content: String, tap: Tap).void }
      def initialize(content, tap: T.unsafe(nil))
        super()

        @content = content.dup.force_encoding("UTF-8")
        @tap = tap
      end

      def load(config:)
        @config = config

        instance_eval(content, __FILE__, __LINE__)
      end
    end

    # Loads a cask from a path.
    class FromPathLoader < AbstractContentLoader
      sig {
        overridable.params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
                   .returns(T.nilable(T.attached_class))
      }
      def self.try_new(ref, warn: false)
        path = case ref
        when String
          Pathname(ref)
        when Pathname
          ref
        else
          return
        end

        return unless path.expand_path.exist?
        return if invalid_path?(path)
        return unless ::Utils::Path.loadable_package_path?(path, :cask)

        new(path)
      end

      sig { params(pathname: Pathname, valid_extnames: T::Array[String]).returns(T::Boolean) }
      def self.invalid_path?(pathname, valid_extnames: %w[.rb .json])
        return true if valid_extnames.exclude?(pathname.extname)

        @invalid_basenames ||= %w[INSTALL_RECEIPT.json sbom.spdx.json].freeze
        @invalid_basenames.include?(pathname.basename.to_s)
      end

      attr_reader :token, :path

      sig { params(path: T.any(Pathname, String), token: String).void }
      def initialize(path, token: T.unsafe(nil))
        super()

        path = Pathname(path).expand_path

        @token = path.basename(path.extname).to_s
        @path = path
        @tap = Tap.from_path(path) || Homebrew::API.tap_from_source_download(path)
        @from_installed_caskfile = false
      end

      sig { override.params(config: T.nilable(Config)).returns(Cask) }
      def load(config:)
        raise CaskUnavailableError.new(token, "'#{path}' does not exist.")  unless path.exist?
        raise CaskUnavailableError.new(token, "'#{path}' is not readable.") unless path.readable?
        raise CaskUnavailableError.new(token, "'#{path}' is not a file.")   unless path.file?

        @content = path.read(encoding: "UTF-8")
        @config = config

        if !self.class.invalid_path?(path, valid_extnames: %w[.json]) &&
           (from_json = JSON.parse(@content).presence) &&
           from_json.is_a?(Hash)
          return FromAPILoader.new(token, from_json:, path:,
from_installed_caskfile: @from_installed_caskfile).load(config:)
        end

        begin
          instance_eval(content, path).tap do |cask|
            raise CaskUnreadableError.new(token, "'#{path}' does not contain a cask.") unless cask.is_a?(Cask)
          end
        rescue NameError, ArgumentError, ScriptError => e
          error = CaskUnreadableError.new(token, e.message)
          error.set_backtrace e.backtrace
          raise error
        end
      end

      private

      def cask(header_token, **options, &block)
        raise CaskTokenMismatchError.new(token, header_token) if token != header_token

        super(header_token, **options, sourcefile_path: path, &block)
      end
    end

    # Loads a cask from a URI.
    class FromURILoader < FromPathLoader
      sig {
        override.params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
                .returns(T.nilable(T.attached_class))
      }
      def self.try_new(ref, warn: false)
        return if Homebrew::EnvConfig.forbid_packages_from_paths?

        # Cache compiled regex
        @uri_regex ||= begin
          uri_regex = ::URI::RFC2396_PARSER.make_regexp
          Regexp.new("\\A#{uri_regex.source}\\Z", uri_regex.options)
        end

        uri = ref.to_s
        return unless uri.match?(@uri_regex)

        uri = URI(uri)
        return unless uri.path

        new(uri)
      end

      attr_reader :url, :name

      sig { params(url: T.any(URI::Generic, String)).void }
      def initialize(url)
        @url = URI(url)
        @name = File.basename(T.must(@url.path))
        super Cache.path/name
      end

      def load(config:)
        path.dirname.mkpath

        if ALLOWED_URL_SCHEMES.exclude?(url.scheme)
          raise UnsupportedInstallationMethod,
                "Non-checksummed download of #{name} formula file from an arbitrary URL is unsupported! " \
                "`brew version-install` to install a formula file from your own custom tap " \
                "instead."
        end

        begin
          ohai "Downloading #{url}"
          ::Utils::Curl.curl_download url.to_s, to: path
        rescue ErrorDuringExecution
          raise CaskUnavailableError.new(token, "Failed to download #{Formatter.url(url)}.")
        end

        super
      end
    end

    # Loads a cask from a specific tap.
    class FromTapLoader < FromPathLoader
      sig { returns(Tap) }
      attr_reader :tap

      sig {
        override(allow_incompatible: true) # rubocop:todo Sorbet/AllowIncompatibleOverride
          .params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
          .returns(T.nilable(T.any(T.attached_class, FromAPILoader)))
      }
      def self.try_new(ref, warn: false)
        ref = ref.to_s

        return unless (token_tap_type = CaskLoader.tap_cask_token_type(ref, warn:))

        token, tap, type = token_tap_type

        if type == :migration && tap.core_cask_tap? && (loader = FromAPILoader.try_new(token))
          loader
        else
          new("#{tap}/#{token}")
        end
      end

      sig { params(tapped_token: String).void }
      def initialize(tapped_token)
        tap, token = Tap.with_cask_token(tapped_token)
        cask = CaskLoader.find_cask_in_tap(token, tap)
        super cask
      end

      sig { override.params(config: T.nilable(Config)).returns(Cask) }
      def load(config:)
        raise TapCaskUnavailableError.new(tap, token) unless T.must(tap).installed?

        super
      end
    end

    # Loads a cask from an existing {Cask} instance.
    class FromInstanceLoader
      include ILoader

      sig {
        params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
          .returns(T.nilable(T.attached_class))
      }
      def self.try_new(ref, warn: false)
        new(ref) if ref.is_a?(Cask)
      end

      sig { params(cask: Cask).void }
      def initialize(cask)
        @cask = cask
      end

      def load(config:)
        @cask
      end
    end

    # Loads a cask from the JSON API.
    class FromAPILoader
      include ILoader

      sig { returns(String) }
      attr_reader :token

      sig { returns(Pathname) }
      attr_reader :path

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      attr_reader :from_json

      sig {
        params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
          .returns(T.nilable(T.attached_class))
      }
      def self.try_new(ref, warn: false)
        return if Homebrew::EnvConfig.no_install_from_api?
        return unless ref.is_a?(String)
        return unless (token = ref[HOMEBREW_DEFAULT_TAP_CASK_REGEX, :token])
        if Homebrew::API.cask_tokens.exclude?(token) &&
           !Homebrew::API.cask_renames.key?(token)
          return
        end

        ref = "#{CoreCaskTap.instance}/#{token}"

        token, tap, = CaskLoader.tap_cask_token_type(ref, warn:)
        new("#{tap}/#{token}")
      end

      sig {
        params(
          token:                   String,
          from_json:               T.nilable(T::Hash[String, T.untyped]),
          path:                    T.nilable(Pathname),
          from_installed_caskfile: T::Boolean,
        ).void
      }
      def initialize(token, from_json: T.unsafe(nil), path: nil, from_installed_caskfile: false)
        @token = token.sub(%r{^homebrew/(?:homebrew-)?cask/}i, "")
        @sourcefile_path = path || Homebrew::API.cached_cask_json_file_path
        @path = path || CaskLoader.default_path(@token)
        @from_json = from_json
        @from_installed_caskfile = from_installed_caskfile
      end

      def load(config:)
        json_cask = from_json
        json_cask ||= if Homebrew::EnvConfig.use_internal_api?
          Homebrew::API::Internal.cask_hashes.fetch(token)
        else
          Homebrew::API::Cask.all_casks.fetch(token)
        end

        cask_struct = Homebrew::API::Cask.generate_cask_struct_hash(json_cask, ignore_types: @from_installed_caskfile)

        cask_options = {
          loaded_from_api: true,
          api_source:      json_cask,
          sourcefile_path: @sourcefile_path,
          source:          JSON.pretty_generate(json_cask),
          config:,
          loader:          self,
        }

        if (tap_string = cask_struct.tap_string)
          cask_options[:tap] = Tap.fetch(tap_string)
        end

        api_cask = Cask.new(token, **cask_options) do
          version cask_struct.version
          sha256 cask_struct.sha256

          url(*cask_struct.url_args, **cask_struct.url_kwargs)
          cask_struct.names.each do |cask_name|
            name cask_name
          end
          desc cask_struct.desc if cask_struct.desc?
          homepage cask_struct.homepage if cask_struct.homepage?

          deprecate!(**cask_struct.deprecate_args) if cask_struct.deprecate?
          disable!(**cask_struct.disable_args) if cask_struct.disable?

          auto_updates cask_struct.auto_updates if cask_struct.auto_updates?
          conflicts_with(**cask_struct.conflicts_with_args) if cask_struct.conflicts?

          cask_struct.renames.each do |from, to|
            rename from, to
          end

          if cask_struct.depends_on?
            args = cask_struct.depends_on_args
            begin
              depends_on(**args)
            rescue MacOSVersion::Error => e
              odebug "Ignored invalid macOS version dependency in cask '#{token}': #{args.inspect} (#{e.message})"
              nil
            end
          end

          container(**cask_struct.container_args) if cask_struct.container?

          cask_struct.artifacts(appdir:).each do |key, args, kwargs, block|
            send(key, *args, **kwargs, &block)
          end

          caveats cask_struct.caveats(appdir:) if cask_struct.caveats?
        end
        api_cask.populate_from_api!(cask_struct)
        api_cask
      end
    end

    # Loader which tries loading casks from tap paths, failing
    # if the same token exists in multiple taps.
    class FromNameLoader < FromTapLoader
      sig {
        override.params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
                .returns(T.nilable(T.any(T.attached_class, FromAPILoader)))
      }
      def self.try_new(ref, warn: false)
        return unless ref.is_a?(String)
        return unless ref.match?(/\A#{HOMEBREW_TAP_CASK_TOKEN_REGEX}\Z/o)

        token = ref

        # If it exists in the default tap, never treat it as ambiguous with another tap.
        if (core_cask_tap = CoreCaskTap.instance).installed? &&
           (core_cask_loader = super("#{core_cask_tap}/#{token}", warn:))&.path&.exist?
          return core_cask_loader
        end

        loaders = Tap.select { |tap| tap.installed? && !tap.core_cask_tap? }
                     .filter_map { |tap| super("#{tap}/#{token}", warn:) }
                     .uniq(&:path)
                     .select { |loader| loader.is_a?(FromAPILoader) || loader.path.exist? }

        case loaders.count
        when 1
          loaders.first
        when 2..Float::INFINITY
          raise TapCaskAmbiguityError.new(token, loaders)
        end
      end
    end

    # Loader which loads a cask from the installed cask file.
    class FromInstalledPathLoader < FromPathLoader
      sig {
        override.params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
                .returns(T.nilable(T.attached_class))
      }
      def self.try_new(ref, warn: false)
        token = if ref.is_a?(String)
          ref
        elsif ref.is_a?(Pathname)
          ref.basename(ref.extname).to_s
        end
        return unless token

        possible_installed_cask = Cask.new(token)
        return unless (installed_caskfile = possible_installed_cask.installed_caskfile)

        new(installed_caskfile)
      end

      sig { params(path: T.any(Pathname, String), token: String).void }
      def initialize(path, token: "")
        super

        installed_tap = Cask.new(@token).tab.tap
        @tap = installed_tap if installed_tap
        @from_installed_caskfile = true
      end
    end

    # Pseudo-loader which raises an error when trying to load the corresponding cask.
    class NullLoader < FromPathLoader
      sig {
        override.params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
                .returns(T.nilable(T.attached_class))
      }
      def self.try_new(ref, warn: false)
        return if ref.is_a?(Cask)
        return if ref.is_a?(URI::Generic)

        new(ref)
      end

      sig { params(ref: T.any(String, Pathname)).void }
      def initialize(ref)
        token = File.basename(ref, ".rb")
        super CaskLoader.default_path(token)
      end

      def load(config:)
        raise CaskUnavailableError.new(token, "No Cask with this name exists.")
      end
    end

    def self.path(ref)
      self.for(ref, need_path: true).path
    end

    def self.load(ref, config: nil, warn: true)
      self.for(ref, warn:).load(config:)
    end

    sig { params(tapped_token: String, warn: T::Boolean).returns(T.nilable([String, Tap, T.nilable(Symbol)])) }
    def self.tap_cask_token_type(tapped_token, warn:)
      return unless (tap_with_token = Tap.with_cask_token(tapped_token))

      tap, token = tap_with_token

      type = nil

      if (new_token = tap.cask_renames[token].presence)
        old_token = tap.core_cask_tap? ? token : tapped_token
        token = new_token
        new_token = tap.core_cask_tap? ? token : "#{tap}/#{token}"
        type = :rename
      elsif (new_tap_name = tap.tap_migrations[token].presence)
        new_tap, new_token = Tap.with_cask_token(new_tap_name)
        unless new_tap
          if new_tap_name.include?("/")
            new_tap = Tap.fetch(new_tap_name)
            new_token = token
          else
            new_tap = tap
            new_token = new_tap_name
          end
        end
        new_tap.ensure_installed!
        new_tapped_token = "#{new_tap}/#{new_token}"

        if tapped_token != new_tapped_token
          old_token = tap.core_cask_tap? ? token : tapped_token
          return unless (token_tap_type = tap_cask_token_type(new_tapped_token, warn: false))

          token, tap, = token_tap_type
          new_token = new_tap.core_cask_tap? ? token : "#{tap}/#{token}"
          type = :migration
        end
      end

      opoo "Cask #{old_token} was renamed to #{new_token}." if warn && old_token && new_token

      [token, tap, type]
    end

    def self.for(ref, need_path: false, warn: true)
      [
        FromInstanceLoader,
        FromContentLoader,
        FromURILoader,
        FromAPILoader,
        FromTapLoader,
        FromNameLoader,
        FromPathLoader,
        FromInstalledPathLoader,
        NullLoader,
      ].each do |loader_class|
        if (loader = loader_class.try_new(ref, warn:))
          $stderr.puts "#{$PROGRAM_NAME} (#{loader.class}): loading #{ref}" if verbose? && debug?
          return loader
        end
      end
    end

    sig { params(ref: String, config: T.nilable(Config), warn: T::Boolean).returns(Cask) }
    def self.load_prefer_installed(ref, config: nil, warn: true)
      tap, token = Tap.with_cask_token(ref)
      token ||= ref
      tap ||= Cask.new(ref).tab.tap

      if tap.nil?
        self.load(token, config:, warn:)
      else
        begin
          self.load("#{tap}/#{token}", config:, warn:)
        rescue CaskUnavailableError
          # cask may be migrated to different tap. Try to search in all taps.
          self.load(token, config:, warn:)
        end
      end
    end

    sig { params(path: Pathname, config: T.nilable(Config), warn: T::Boolean).returns(Cask) }
    def self.load_from_installed_caskfile(path, config: nil, warn: true)
      loader = FromInstalledPathLoader.try_new(path, warn:)
      loader ||= NullLoader.new(path)

      loader.load(config:)
    end

    def self.default_path(token)
      find_cask_in_tap(token.to_s.downcase, CoreCaskTap.instance)
    end

    def self.find_cask_in_tap(token, tap)
      filename = "#{token}.rb"

      tap.cask_files_by_name.fetch(token, tap.cask_dir/filename)
    end
  end
end
