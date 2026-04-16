# typed: strict
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

      sig { overridable.returns(T.nilable(Tap)) }
      attr_reader :tap

      sig { void }
      def initialize
        @content = T.let("", String)
        @tap = T.let(nil, T.nilable(Tap))
        @config = T.let(nil, T.nilable(Config))
      end

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
        @regex ||= T.let(
          begin
            token  = /(?:"[^"]*"|'[^']*')/
            curly  = /\(\s*#{token.source}\s*\)\s*\{.*\}/
            do_end = /\s+#{token.source}\s+do(?:\s*;\s*|\s+).*end/
            /\A\s*cask(?:#{curly.source}|#{do_end.source})\s*\Z/m
          end,
          T.nilable(Regexp),
        )

        return unless content.match?(@regex)

        new(content)
      end

      sig { params(content: String, tap: Tap).void }
      def initialize(content, tap: T.unsafe(nil))
        super()

        @content = T.let(content.dup.force_encoding("UTF-8"), String)
        @tap = T.let(tap, T.nilable(Tap))
      end

      sig { override.params(config: T.nilable(Config)).returns(Cask) }
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

        @invalid_basenames ||= T.let(%w[INSTALL_RECEIPT.json sbom.spdx.json].freeze, T.nilable(T::Array[String]))
        @invalid_basenames.include?(pathname.basename.to_s)
      end

      sig { returns(String) }
      attr_reader :token

      sig { returns(Pathname) }
      attr_reader :path

      sig { params(path: T.any(Pathname, String), token: String).void }
      def initialize(path, token: T.unsafe(nil))
        super()

        path = Pathname(path).expand_path

        @token = T.let(path.basename(path.extname).basename(".internal").to_s, String)
        @path = T.let(path, Pathname)
        @tap = T.let(Tap.from_path(path) || Homebrew::API.tap_from_source_download(path), T.nilable(Tap))
        @from_installed_caskfile = T.let(false, T::Boolean)
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
          begin
            from_internal_json = path.to_s.end_with?(".internal.json")
            return FromAPILoader.new(
              token,
              from_json:,
              path:,
              from_installed_caskfile: @from_installed_caskfile,
              from_internal_json:,
            ).load(config:)
          rescue CaskInvalidError => e
            if @from_installed_caskfile
              error = CaskUnreadableError.new(token, e.reason)
              error.set_backtrace e.backtrace
              raise error
            end
            raise
          end
        end

        begin
          instance_eval(content, path.to_s).tap do |cask|
            raise CaskUnreadableError.new(token, "'#{path}' does not contain a cask.") unless cask.is_a?(Cask)
          end
        rescue NameError, ArgumentError, ScriptError => e
          error = CaskUnreadableError.new(token, e.message)
          error.set_backtrace e.backtrace
          raise error
        rescue CaskInvalidError => e # e.g. NoMethodError from removed DSL methods, wrapped
          # as CaskInvalidError by Cask#refresh before reaching here.
          if @from_installed_caskfile
            error = CaskUnreadableError.new(token, e.reason)
            error.set_backtrace e.backtrace
            raise error
          end
          raise
        end
      end

      private

      sig {
        override.params(
          header_token: String,
          options:      T.untyped,
          block:        T.nilable(T.proc.bind(DSL).void),
        ).returns(Cask)
      }
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
        @uri_regex ||= T.let(
          begin
            uri_regex = ::URI::RFC2396_PARSER.make_regexp
            Regexp.new("\\A#{uri_regex.source}\\Z", uri_regex.options)
          end,
          T.nilable(Regexp),
        )

        uri = ref.to_s
        return unless uri.match?(@uri_regex)

        uri = URI(uri)
        return unless uri.path

        new(uri)
      end

      sig { returns(URI::Generic) }
      attr_reader :url

      sig { returns(String) }
      attr_reader :name

      sig { params(url: T.any(URI::Generic, String)).void }
      def initialize(url)
        @url = T.let(URI(url), URI::Generic)
        url_path = @url.path
        raise "unexpected nil url.path" unless url_path

        @name = T.let(File.basename(url_path), String)
        super Cache.path/name
      end

      sig { override.params(config: T.nilable(Config)).returns(Cask) }
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
      sig { override.returns(Tap) }
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
        tap_with_token = Tap.with_cask_token(tapped_token)
        raise "unexpected nil Tap.with_cask_token" unless tap_with_token

        tap, token = tap_with_token
        cask = CaskLoader.find_cask_in_tap(token, tap)
        super cask
        @tap = T.let(tap, Tap)
      end

      sig { override.params(config: T.nilable(Config)).returns(Cask) }
      def load(config:)
        raise TapCaskUnavailableError.new(tap, token) unless tap.installed?

        super
      end
    end

    # Loads a cask from an existing {Cask} instance.
    class FromInstanceLoader
      include ILoader

      sig {
        params(ref: T.any(String, Pathname, Cask, URI::Generic), warn: T::Boolean)
          .returns(T.nilable(FromInstanceLoader))
      }
      def self.try_new(ref, warn: false)
        new(ref) if ref.is_a?(Cask)
      end

      sig { params(cask: Cask).void }
      def initialize(cask)
        @cask = cask
      end

      # This is a false positive incompatibililty warning, due to Kernel#load being overridden.
      sig { override(allow_incompatible: true).params(config: T.nilable(Config)).returns(Cask) } # rubocop:disable Sorbet/AllowIncompatibleOverride
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
          .returns(T.nilable(FromAPILoader))
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
          from_internal_json:      T::Boolean,
        ).void
      }
      def initialize(token, from_json: T.unsafe(nil), path: nil, from_installed_caskfile: false,
                     from_internal_json: false)
        @token = T.let(token.sub(%r{^homebrew/(?:homebrew-)?cask/}i, ""), String)
        @sourcefile_path = T.let(
          if path
            path
          elsif from_json
            from_internal_json ? Homebrew::API::Internal.cached_cask_json_file_path : Homebrew::API::Cask.cached_json_file_path
          else
            Homebrew::API.cached_cask_json_file_path
          end,
          Pathname,
        )
        @path = T.let(path || CaskLoader.default_path(@token), Pathname)
        @from_json = from_json
        @from_installed_caskfile = from_installed_caskfile
        @from_internal_json = from_internal_json
      end

      # This is a false positive incompatibililty warning, due to Kernel#load being overridden.
      sig { override(allow_incompatible: true).params(config: T.nilable(Config)).returns(Cask) } # rubocop:disable Sorbet/AllowIncompatibleOverride
      def load(config:)
        if (api_source = from_json)
          if @from_internal_json
            load_from_internal_json(config:, api_source:)
          else
            load_from_json(config:, api_source:)
          end
        elsif Homebrew::EnvConfig.use_internal_api?
          load_from_internal_api(config:)
        else
          load_from_api(config:)
        end
      end

      private

      sig { params(config: T.nilable(Config)).returns(Cask) }
      def load_from_api(config:)
        api_source = Homebrew::API::Cask.all_casks.fetch(token)
        tap_git_head = api_source["tap_git_head"]
        cask_struct = Homebrew::API::Cask::CaskStructGenerator.generate_cask_struct_hash(
          api_source, ignore_types: @from_installed_caskfile
        )

        load_from_struct(config:, cask_struct:, api_source:, tap_git_head:)
      end

      sig { params(config: T.nilable(Config)).returns(Cask) }
      def load_from_internal_api(config:)
        cask_struct = Homebrew::API::Internal.cask_struct(token)
        api_source = Homebrew::API::Internal.cask_hashes.fetch(token)
        tap_git_head = Homebrew::API::Internal.cask_tap_git_head

        load_from_struct(config:, cask_struct:, api_source:, tap_git_head:, internal_api: true)
      end

      sig { params(config: T.nilable(Config), api_source: T::Hash[String, T.untyped]).returns(Cask) }
      def load_from_json(config:, api_source:)
        tap_git_head = api_source["tap_git_head"]
        cask_struct = Homebrew::API::Cask::CaskStructGenerator.generate_cask_struct_hash(
          api_source, ignore_types: @from_installed_caskfile
        )

        load_from_struct(config:, cask_struct:, api_source:, tap_git_head:)
      end

      sig { params(config: T.nilable(Config), api_source: T::Hash[String, T.untyped]).returns(Cask) }
      def load_from_internal_json(config:, api_source:)
        api_source = api_source.dup
        tap_git_head = api_source.delete("tap_git_head")
        cask_struct = Homebrew::API::CaskStruct.deserialize(api_source)

        load_from_struct(config:, cask_struct:, api_source:, tap_git_head:, internal_api: true)
      end

      sig {
        params(
          config:       T.nilable(Config),
          cask_struct:  Homebrew::API::CaskStruct,
          api_source:   T::Hash[String, T.untyped],
          tap_git_head: T.nilable(String),
          internal_api: T::Boolean,
        ).returns(Cask)
      }
      def load_from_struct(config:, cask_struct:, api_source:, tap_git_head:, internal_api: false)
        cask_options = {
          loaded_from_api:          true,
          loaded_from_internal_api: internal_api,
          api_source:,
          sourcefile_path:          @sourcefile_path,
          source:                   JSON.pretty_generate(api_source),
          config:,
          loader:                   self,
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

          if cask_struct.container?
            container(nested: cask_struct.container_args[:nested], type: cask_struct.container_args[:type])
          end

          cask_struct.artifacts(appdir:).each do |key, args, kwargs, block|
            send(key, *args, **kwargs, &block)
          end

          caveats T.must(cask_struct.caveats(appdir:)) if cask_struct.caveats?

          if cask_struct.caveats_rosetta
            caveats do
              # Dynamically defined via `caveat :requires_rosetta` — Sorbet can't resolve it.
              public_send(:requires_rosetta) # rubocop:disable Style/SendWithLiteralMethodName
            end
          end
        end
        api_cask.populate_from_api!(cask_struct, tap_git_head:)
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
          ref.basename(ref.extname).basename(".internal").to_s
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
        @from_installed_caskfile = T.let(true, T::Boolean)
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

      sig { override.params(config: T.nilable(Config)).returns(Cask) }
      def load(config:)
        raise CaskUnavailableError.new(token, "No Cask with this name exists.")
      end
    end

    # NOTE: Using `WithoutRuntime` to avoid Sorbet wrapping this method,
    # which would interfere with RSpec mocking of this class method.
    T::Sig::WithoutRuntime.sig { params(ref: T.any(String, Pathname, Cask, URI::Generic)).returns(Pathname) }
    def self.path(ref)
      T.cast(self.for(ref, need_path: true), T.any(FromAPILoader, FromPathLoader)).path
    end

    # NOTE: Using `WithoutRuntime` to avoid Sorbet wrapping this method,
    # which would interfere with RSpec mocking of this class method.
    T::Sig::WithoutRuntime.sig {
      params(ref: T.any(String, Symbol, Pathname, Cask, URI::Generic), config: T.nilable(Config),
             warn: T::Boolean).returns(Cask)
    }
    def self.load(ref, config: nil, warn: true)
      normalized_ref = ref.is_a?(Symbol) ? ref.to_s : ref
      self.for(normalized_ref, warn:).load(config:)
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

    # NOTE: Using `WithoutRuntime` to avoid Sorbet wrapping this method,
    # which would interfere with RSpec mocking of this class method.
    T::Sig::WithoutRuntime.sig {
      params(ref: T.any(String, Pathname, Cask, URI::Generic), need_path: T::Boolean, warn: T::Boolean)
        .returns(ILoader)
    }
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

      raise CaskError, "No cask loader found for #{ref.inspect}"
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

    sig { params(token: T.any(String, Symbol)).returns(Pathname) }
    def self.default_path(token)
      find_cask_in_tap(token.to_s.downcase, CoreCaskTap.instance)
    end

    sig { params(token: String, tap: Tap).returns(Pathname) }
    def self.find_cask_in_tap(token, tap)
      filename = "#{token}.rb"

      tap.cask_files_by_name.fetch(token, tap.cask_dir/filename)
    end
  end
end
