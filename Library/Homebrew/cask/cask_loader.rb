# typed: strict
# frozen_string_literal: true

require "cask/cask"
require "utils/output"
require "utils/path"
require "extend/hash/keys"
require "extend/ENV/sensitive"
require "api"
require "trust"

module Cask
  # Loads a cask from various sources.
  module CaskLoader
    extend Context
    extend ::Utils::Output::Mixin

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
          block:        T.nilable(T.proc.bind(DSL).void),
        ).returns(Cask)
      }
      def cask(header_token, &block)
        Cask.new(header_token, source: content, tap:, config: @config, &block)
      end
    end

    # Loads a cask from a string.
    class FromContentLoader < AbstractContentLoader
      T::Sig::WithoutRuntime.sig {
        params(_ref: String, warn: T::Boolean).returns(NilClass)
      }
      def self.try_new(_ref, warn: false)
        CaskLoader.odeprecated "Cask::CaskLoader::FromContentLoader.try_new", "Cask::CaskLoader.from_content"
        nil
      end

      sig { params(content: String, tap: T.nilable(Tap)).void }
      def initialize(content, tap: nil)
        super()

        @content = T.let(content.dup.force_encoding("UTF-8"), String)
        @tap = tap
      end

      sig { override.params(config: T.nilable(Config)).returns(Cask) }
      def load(config:)
        @config = config

        cask = ENV.clear_sensitive_environment_for_eval! do
          instance_eval(content, "(cask content)")
        end
        raise CaskUnavailableError.new("(content)", "Source does not contain a cask.") unless cask.is_a?(Cask)

        cask
      end
    end

    # Loads a cask from a path.
    class FromPathLoader < AbstractContentLoader
      T::Sig::WithoutRuntime.sig {
        overridable.params(_ref: String, warn: T::Boolean).returns(T.nilable(T.any(T.attached_class, FromAPILoader)))
      }
      def self.try_new(_ref, warn: false)
        CaskLoader.odeprecated "Cask::CaskLoader::FromPathLoader.try_new", "Cask::CaskLoader.from_path"
        nil
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

      sig { params(from_installed_caskfile: T::Boolean).void }
      attr_writer :from_installed_caskfile

      sig { params(path: T.any(Pathname, String), token: T.nilable(String)).void }
      def initialize(path, token: nil)
        super()

        path = Pathname(path).expand_path

        @token = T.let(CaskLoader.token_from_path(path), String)
        @path = T.let(path, Pathname)
        @tap = T.let(Tap.from_path(path), T.nilable(Tap))
        @from_installed_caskfile = T.let(false, T::Boolean)
        @api_fallback = T.let(true, T::Boolean)
      end

      sig { override.params(config: T.nilable(Config)).returns(Cask) }
      def load(config:)
        raise CaskUnavailableError.new(token, "'#{path}' does not exist.")  unless path.exist?
        raise CaskUnavailableError.new(token, "'#{path}' is not readable.") unless path.readable?
        raise CaskUnavailableError.new(token, "'#{path}' is not a file.")   unless path.file?

        source_tap = tap if path.extname == ".rb"
        Homebrew::Trust.require_trusted_cask!(token, path, tap: source_tap)

        @content = path.read(encoding: "UTF-8")
        @config = config

        if !self.class.invalid_path?(path, valid_extnames: %w[.json]) &&
           (from_json = JSON.parse(@content)) &&
           from_json.is_a?(Hash) &&
           (@from_installed_caskfile || from_json.present?)
          begin
            from_internal_json = path.to_s.end_with?(".internal.json")
            return FromAPILoader.new(
              token,
              from_json:,
              path:,
              from_installed_caskfile: @from_installed_caskfile,
              from_internal_json:,
              api_fallback:            @api_fallback,
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
          ENV.clear_sensitive_environment_for_eval! do
            cask = instance_eval(content, path.to_s)
            raise CaskUnreadableError.new(token, "'#{path}' does not contain a cask.") unless cask.is_a?(Cask)

            cask
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
          block:        T.nilable(T.proc.bind(DSL).void),
        ).returns(Cask)
      }
      def cask(header_token, &block)
        raise CaskTokenMismatchError.new(token, header_token) if token != header_token

        Cask.new(header_token, sourcefile_path: path, source: content, tap:,
                               loaded_from_metadata: @from_installed_caskfile, config: @config, &block)
      end
    end

    # Loads a cask from a specific tap.
    class FromTapLoader < FromPathLoader
      sig { override.returns(Tap) }
      attr_reader :tap

      sig {
        override.params(ref: String, warn: T::Boolean)
                .returns(T.nilable(T.any(T.attached_class, FromAPILoader)))
      }
      def self.try_new(ref, warn: false)
        return unless (token_tap_type = CaskLoader.tap_cask_token_type(ref, warn:))

        loader_from_token_tap_type(token_tap_type)
      end

      sig {
        params(token_tap_type: [String, Tap, T.nilable(Symbol)])
          .returns(T.nilable(T.any(T.attached_class, FromAPILoader)))
      }
      def self.loader_from_token_tap_type(token_tap_type)
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

    # Loads a cask from the JSON API.
    class FromAPILoader
      include ILoader

      sig { returns(String) }
      attr_reader :token

      sig { returns(Pathname) }
      attr_reader :path

      sig { returns(T.nilable(T::Hash[String, T.untyped])) }
      attr_reader :from_json

      sig { returns(T::Boolean) }
      attr_reader :api_fallback

      sig {
        params(ref: String, warn: T::Boolean)
          .returns(T.nilable(FromAPILoader))
      }
      def self.try_new(ref, warn: false)
        return if Homebrew::EnvConfig.no_install_from_api?
        return unless (token = ref[HOMEBREW_DEFAULT_TAP_CASK_REGEX, :token])
        if !Homebrew::API.cask_token?(token) &&
           !Homebrew::API.cask_aliases.key?(token) &&
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
          api_fallback:            T::Boolean,
        ).void
      }
      def initialize(token, from_json: nil, path: nil, from_installed_caskfile: false,
                     from_internal_json: false, api_fallback: true)
        @token = T.let(token.sub(%r{^homebrew/(?:homebrew-)?cask/}i, ""), String)
        @sourcefile_path = T.let(
          if path
            path
          elsif from_json
            from_internal_json ? Homebrew::API::Internal.cached_packages_json_file_path : Homebrew::API::Cask.cached_json_file_path
          else
            Homebrew::API.cached_cask_json_file_path
          end,
          Pathname,
        )
        @path = T.let(path || CaskLoader.default_path(@token), Pathname)
        @from_json = from_json
        @from_installed_caskfile = from_installed_caskfile
        @from_internal_json = from_internal_json
        @api_fallback = api_fallback
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
        else
          load_from_internal_api(config:)
        end
      end

      private

      sig { params(config: T.nilable(Config)).returns(Cask) }
      def load_from_internal_api(config:)
        cask_struct = Homebrew::API::Internal.cask_struct(token)
        api_source = Homebrew::API::Internal.cask_hash(token)
        raise KeyError, "key not found: #{token.inspect}" if api_source.nil?

        tap_git_head = Homebrew::API::Internal.cask_tap_git_head

        load_from_struct(config:, cask_struct:, api_source:, tap_git_head:, internal_api: true)
      end

      sig { params(config: T.nilable(Config), api_source: T::Hash[String, T.untyped]).returns(Cask) }
      def load_from_json(config:, api_source:)
        if @from_installed_caskfile
          api_source = api_source.dup
          api_source["version"] = api_source["version"].presence
          api_source["version"] ||= @sourcefile_path.dirname.dirname.dirname.basename.to_s.presence
          if api_source["version"].nil? || api_source["artifacts"].nil?
            installed_tab = CaskLoader.load_installed_tab(token)
            api_source["version"] ||= installed_tab.version.presence
            api_source["artifacts"] ||= CaskLoader.resolve_installed_artifacts(
              token, installed_tab.uninstall_artifacts, tap: installed_tab.tap, api_fallback: @api_fallback
            )
          end
        end

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
          loaded_from_metadata:     @from_installed_caskfile,
          api_source:,
          sourcefile_path:          @sourcefile_path,
          source:                   JSON.pretty_generate(api_source),
          config:,
          loader:                   self,
        }

        if @from_installed_caskfile && (installed_tap = CaskLoader.load_installed_tab(token).tap)
          cask_options[:tap] = installed_tap
        elsif (tap_string = cask_struct.tap_string)
          cask_options[:tap] = Tap.fetch(tap_string)
        end

        api_cask = Cask.new(token, **cask_options) do
          localised_cask_struct = if cask_struct.language_variations.empty?
            cask_struct
          else
            cask_struct.localise(cask.config.languages)
          end

          version localised_cask_struct.version
          sha256 localised_cask_struct.sha256

          url(*localised_cask_struct.url_args, **localised_cask_struct.url_kwargs)
          localised_cask_struct.names.each do |cask_name|
            name cask_name
          end
          desc localised_cask_struct.desc if localised_cask_struct.desc?
          homepage localised_cask_struct.homepage if localised_cask_struct.homepage?

          deprecate!(**localised_cask_struct.deprecate_args) if localised_cask_struct.deprecate?
          disable!(**localised_cask_struct.disable_args) if localised_cask_struct.disable?

          auto_updates localised_cask_struct.auto_updates if localised_cask_struct.auto_updates?
          conflicts_with(**localised_cask_struct.conflicts_with_args) if localised_cask_struct.conflicts?

          localised_cask_struct.renames.each do |from, to|
            rename from, to
          end

          if localised_cask_struct.depends_on?
            args = localised_cask_struct.depends_on_args
            begin
              depends_on(**args)
            rescue MacOSVersion::Error => e
              odebug "Ignored invalid macOS version dependency in cask '#{token}': #{args.inspect} (#{e.message})"
              nil
            end
          end

          if localised_cask_struct.container?
            container(nested: localised_cask_struct.container_args[:nested],
                      type:   localised_cask_struct.container_args[:type])
          end

          localised_cask_struct.artifacts(appdir:).each do |key, args, kwargs, block|
            unless DSL::ARTIFACT_DSL_METHODS.include?(key)
              odebug "Ignoring unsupported artifact stanza '#{key}' in cask '#{token}'"
              next
            end

            public_send(key, *args, **kwargs, &block)
          end

          if (caveats_string = localised_cask_struct.caveats(appdir:).presence)
            caveats caveats_string
          end

          if localised_cask_struct.caveats_rosetta
            caveats do
              T.bind(self, DSL::Caveats)
              requires_rosetta
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
      extend ::Utils::Output::Mixin

      sig {
        override.params(ref: String, warn: T::Boolean)
                .returns(T.nilable(T.any(T.attached_class, FromAPILoader)))
      }
      def self.try_new(ref, warn: false)
        return unless ref.match?(/\A#{HOMEBREW_TAP_CASK_TOKEN_REGEX}\Z/o)

        token = ref.downcase

        # If it exists in the default tap, never treat it as ambiguous with another tap.
        if (core_cask_tap = CoreCaskTap.instance).installed? && (token_tap_type = CaskLoader.tap_cask_token_type(
          "#{core_cask_tap}/#{token}", warn: false
        ))
          migrated_token, migrated_tap, type = token_tap_type

          if warn && [:rename, :migration].include?(type) &&
             !(type == :migration && migrated_tap.core_tap?)
            opoo "Cask #{token} was renamed to " \
                 "#{migrated_tap.core_cask_tap? ? migrated_token : "#{migrated_tap}/#{migrated_token}"}."
          end

          if (core_cask_loader = loader_from_token_tap_type(token_tap_type))&.path&.exist?
            return core_cask_loader
          end
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
      T::Sig::WithoutRuntime.sig {
        override.params(_ref: String, warn: T::Boolean, api_fallback: T::Boolean).returns(NilClass)
      }
      def self.try_new(_ref, warn: false, api_fallback: true)
        CaskLoader.odeprecated "Cask::CaskLoader::FromInstalledPathLoader.try_new", "Cask::CaskLoader.load_from_installed_caskfile"
        nil
      end

      sig { params(path: T.any(Pathname, String), token: String, api_fallback: T::Boolean).void }
      def initialize(path, token: "", api_fallback: true)
        super(path, token:)

        installed_tap = Cask.new(@token).tab.tap
        @tap = installed_tap if installed_tap
        @from_installed_caskfile = T.let(true, T::Boolean)
        @api_fallback = api_fallback
      end
    end

    # Pseudo-loader which raises an error when trying to load the corresponding cask.
    class NullLoader < FromPathLoader
      T::Sig::WithoutRuntime.sig { override.params(_ref: String, warn: T::Boolean).returns(NilClass) }
      def self.try_new(_ref, warn: false)
        CaskLoader.odeprecated "Cask::CaskLoader::NullLoader.try_new", "Cask::CaskLoader::NullLoader.new"
        nil
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

    # Deprecated entry points. They never discover or evaluate source files.
    class FromURILoader
      T::Sig::WithoutRuntime.sig { params(_ref: String, warn: T::Boolean).returns(NilClass) }
      def self.try_new(_ref, warn: false)
        CaskLoader.odeprecated "Cask::CaskLoader::FromURILoader.try_new", "Cask::CaskLoader.from_path"
        nil
      end

      T::Sig::WithoutRuntime.sig { params(url: String).void }
      def initialize(url)
        CaskLoader.odeprecated "Cask::CaskLoader::FromURILoader.new", "Cask::CaskLoader.from_path"
        raise CaskUnavailableError.new(url, "Loading casks from URLs is unsupported.")
      end
    end

    class FromInstanceLoader
      T::Sig::WithoutRuntime.sig { params(_ref: T.any(String, Cask), warn: T::Boolean).returns(NilClass) }
      def self.try_new(_ref, warn: false)
        CaskLoader.odeprecated "Cask::CaskLoader::FromInstanceLoader.try_new", "the existing cask instance"
        nil
      end

      T::Sig::WithoutRuntime.sig { params(cask: Cask).void }
      def initialize(cask)
        CaskLoader.odeprecated "Cask::CaskLoader::FromInstanceLoader.new", "the existing cask instance"
        raise CaskUnavailableError.new(cask.token, "Use the existing cask instance directly.")
      end
    end

    T::Sig::WithoutRuntime.sig {
      params(ref: String, need_path: T::Boolean,
             warn: T::Boolean).returns(T.any(FromAPILoader, FromTapLoader, NullLoader))
    }
    def self.for(ref, need_path: false, warn: true)
      odeprecated "Cask::CaskLoader.for", "Cask::CaskLoader.loader_for"
      loader_for(ref, warn:)
    end

    # NOTE: Using `WithoutRuntime` to avoid Sorbet wrapping this method,
    # which would interfere with RSpec mocking of this class method.
    T::Sig::WithoutRuntime.sig { params(ref: String).returns(Pathname) }
    def self.path(ref)
      loader_for(ref).path
    end

    # Look up a cask by name, without interpreting paths or Ruby source.
    T::Sig::WithoutRuntime.sig {
      params(ref: String, config: T.nilable(Config),
             warn: T::Boolean).returns(Cask)
    }
    def self.load(ref, config: nil, warn: true)
      loader_for(ref, warn:).load(config:)
    end

    # @api private
    # Load a parent-selected source file. Homebrew/brew callers only.
    T::Sig::WithoutRuntime.sig { params(path: T.any(String, Pathname), config: T.nilable(Config)).returns(Cask) }
    def self.from_path(path, config: nil)
      path = Pathname(path)
      raise CaskUnavailableError.new(path.to_s, "Invalid cask source path.") if FromPathLoader.invalid_path?(path)

      FromPathLoader.new(path).load(config:)
    end

    # @api private
    # Load a registered tap source file for auditing or CI.
    T::Sig::WithoutRuntime.sig { params(path: T.any(String, Pathname)).returns(Cask) }
    def self.from_tap_path(path)
      tap_path = ::Utils::Path.tap_package_path(Pathname(path), :cask)
      raise CaskUnavailableError.new(path.to_s, "Not a registered tap source file.") unless tap_path

      from_path(tap_path)
    end

    # @api private
    # Evaluate explicitly supplied source. Homebrew/brew callers only.
    T::Sig::WithoutRuntime.sig { params(content: String, config: T.nilable(Config), tap: T.nilable(Tap)).returns(Cask) }
    def self.from_content(content, config: nil, tap: nil)
      FromContentLoader.new(content, tap:).load(config:)
    end

    # Loads a bare cask token without interpreting it as source, a path or a URI.
    sig { params(name: String, warn: T::Boolean).returns(Cask) }
    def self.load_from_name(name, warn: true)
      if !name.match?(/\A#{HOMEBREW_TAP_CASK_TOKEN_REGEX}\z/o) || ::Utils::INVALID_PATH_COMPONENTS.include?(name)
        raise CaskUnavailableError.new(name, "Invalid cask token.")
      end

      load(name, warn:)
    end

    sig { params(tapped_token: String, warn: T::Boolean).returns(T.nilable([String, Tap, T.nilable(Symbol)])) }
    def self.tap_cask_token_type(tapped_token, warn:)
      return unless (tap_with_token = Tap.with_cask_token(tapped_token))

      tap, token = tap_with_token

      type = nil

      alias_table_key = tap.core_cask_tap? ? token : "#{tap}/#{token}"

      if (alias_target = tap.cask_alias_table[alias_table_key].presence)
        token = ::Utils.name_from_full_name(alias_target)
        type = :alias
      elsif (new_token = tap.cask_renames[token].presence)
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

      if warn && old_token && new_token
        destination_exists = find_cask_in_tap(token, tap).exist? ||
                             (tap.core_cask_tap? && !Homebrew::EnvConfig.no_install_from_api? &&
                              Homebrew::API.cask_token?(token))
        opoo "Cask #{old_token} was renamed to #{new_token}." if destination_exists
      end

      [token, tap, type]
    end

    # Select only name-based sources: API, qualified tap then unqualified tap lookup.
    T::Sig::WithoutRuntime.sig {
      params(ref: String, warn: T::Boolean).returns(T.any(FromAPILoader, FromTapLoader, NullLoader))
    }
    def self.loader_for(ref, warn: true)
      unless ::Utils::Path.valid_package_name?(ref)
        opoo "Loading casks from paths, URLs or Ruby source is not supported; use a cask name." if warn
        return NullLoader.new(ref.to_s)
      end

      loader = FromAPILoader.try_new(ref, warn:) ||
               FromTapLoader.try_new(ref, warn:) ||
               FromNameLoader.try_new(ref, warn:) ||
               NullLoader.new(ref)
      $stderr.puts "#{$PROGRAM_NAME} (#{loader.class}): loading #{ref}" if verbose? && debug?
      loader
    end

    # @api private
    # Resolve a name using its receipt's tap, with an installed-source fallback.
    T::Sig::WithoutRuntime.sig { params(ref: String, config: T.nilable(Config), warn: T::Boolean).returns(Cask) }
    def self.load_prefer_installed(ref, config: nil, warn: true)
      unless ::Utils::Path.valid_package_name?(ref)
        raise CaskUnavailableError.new(ref, "Invalid cask name.")
      end

      tap, token = Tap.with_cask_token(ref)
      token ||= ref
      installed_cask = Cask.new(token)
      installed_tap = installed_cask.tab.tap
      tap ||= installed_tap

      begin
        name = tap ? "#{tap}/#{token}" : token
        self.load(name, config:, warn:)
      rescue CaskUnreadableError
        raise
      rescue CaskUnavailableError
        raise if tap && tap != installed_tap

        installed_path = installed_cask.installed_caskfile
        raise unless installed_path

        load_from_installed_caskfile(installed_path, config:, warn:)
      end
    end

    # @api private
    # Load only the recorded installed source file, with optional API artifact recovery.
    T::Sig::WithoutRuntime.sig {
      params(path: Pathname, config: T.nilable(Config), warn: T::Boolean, api_fallback: T::Boolean)
        .returns(Cask)
    }
    def self.load_from_installed_caskfile(path, config: nil, warn: true, api_fallback: true)
      token = token_from_path(path)
      installed_path = Cask.new(token).installed_caskfile
      if installed_path.nil? || path.expand_path != installed_path.expand_path
        raise CaskUnavailableError.new(token, "Not the installed cask metadata file.")
      end

      FromInstalledPathLoader.new(path, api_fallback:).load(config:)
    end

    sig { params(path: Pathname).returns(String) }
    def self.token_from_path(path)
      path.basename(path.extname).basename(".internal").to_s
    end

    # Legacy `.internal.json` files contain full API data rather than the compact installed JSON format.
    sig { params(path: Pathname).returns(T::Boolean) }
    def self.installed_json_caskfile?(path)
      path.extname == ".json" && !path.basename.to_s.end_with?(".internal.json")
    end

    sig { params(path: Pathname).returns(T.nilable(T::Hash[String, T.untyped])) }
    def self.load_installed_json(path)
      return unless installed_json_caskfile?(path)

      json = JSON.parse(path.read)
      json if json.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    sig { params(cask_or_token: T.any(Cask, String)).returns(Tab) }
    def self.load_installed_tab(cask_or_token)
      cask = if cask_or_token.is_a?(Cask)
        cask_or_token
      else
        Cask.new(cask_or_token)
      end
      cask.tab
    rescue JSON::ParserError, NoMethodError, TypeError
      Tab.empty
    end

    sig {
      params(
        token:        String,
        artifacts:    T.nilable(T::Array[T::Hash[T.any(String, Symbol), T.anything]]),
        tap:          T.nilable(Tap),
        api_fallback: T::Boolean,
      ).returns(T::Array[T::Hash[T.any(String, Symbol), T.anything]])
    }
    def self.resolve_installed_artifacts(token, artifacts, tap: nil, api_fallback: true)
      artifacts = artifacts.presence
      return artifacts if artifacts
      return [] unless api_fallback

      begin
        cask = if tap && !tap.core_cask_tap?
          load("#{tap}/#{token}", warn: false)
        elsif (loader = FromAPILoader.try_new(token) || FromNameLoader.try_new(token, warn: false))
          loader.load(config: nil)
        end
        cask&.artifacts_list(uninstall_only: true) || []
      rescue CaskError, MethodDeprecatedError, JSON::ParserError, KeyError, ErrorDuringExecution, SystemExit
        []
      end
    end

    sig {
      params(
        path:          Pathname,
        tab:           T.nilable(Tab),
        fallback_cask: T.nilable(Cask),
        config:        T.nilable(Config),
      ).returns(T.nilable(Cask))
    }
    def self.recover_from_installed_caskfile(path, tab: nil, fallback_cask: nil, config: nil)
      # Only installed metadata has the versioned path layout used to rebuild the cask below.
      return if path.dirname.basename.to_s != "Casks"

      # Read any usable receipt, while retaining the current cask as a fallback for missing receipt data.
      token = token_from_path(path)
      tab ||= load_installed_tab(fallback_cask || token)

      # Ruby uninstall flight blocks cannot be represented by installed JSON and must not be approximated.
      return if tab.uninstall_flight_blocks
      return if fallback_cask&.uninstall_flight_blocks?

      # Prefer exact receipt artifacts, then the current cask and finally the current source definition.
      artifacts = tab.uninstall_artifacts.presence
      artifacts ||= fallback_cask.artifacts_list(uninstall_only: true) if fallback_cask
      artifacts ||= resolve_installed_artifacts(token, nil, tap: tab.tap)

      # Rebuild the installed version from its metadata directory and retain current source path information.
      api_source = {
        "version"   => path.dirname.dirname.dirname.basename.to_s,
        "artifacts" => artifacts,
      }
      api_source["url_specs"] ||= fallback_cask.to_installed_json_hash["url_specs"] if fallback_cask

      # Prefer the installed JSON's source path because it belongs to the installed version.
      if (source_json = load_installed_json(path))
        source_url_specs = source_json["url_specs"]
        api_source["url_specs"] = source_url_specs if source_url_specs.is_a?(Hash)
      end

      # Load through the installed-JSON path so reconstructed artifacts have normal installed paths and behaviour.
      recovered_cask = FromAPILoader.new(
        token,
        from_json:               api_source,
        path:,
        from_installed_caskfile: true,
      ).load(config:)
      recovered_cask unless recovered_cask.uninstall_flight_blocks?
    rescue CaskInvalidError, CaskUnavailableError, MethodDeprecatedError, JSON::ParserError
      # Recovery is best effort; callers treat nil as an unavailable installed cask and use their existing fallback.
      nil
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
