# typed: strict
# frozen_string_literal: true

require "utils/data"

require "json"

require "lazy_object"
require "locale"
require "extend/hash/keys"
require "utils/output"

module Cask
  # Configuration for installing casks.
  #
  # @api internal
  class Config
    include ::Utils::Output::Mixin

    ConfigHash = T.type_alias { T::Hash[Symbol, T.any(LazyObject, String, Pathname, T::Array[String])] }
    DEFAULT_DIRS = T.let(
      {
        appdir:               "/Applications",
        appimagedir:          "~/Applications",
        keyboard_layoutdir:   "/Library/Keyboard Layouts",
        colorpickerdir:       "~/Library/ColorPickers",
        prefpanedir:          "~/Library/PreferencePanes",
        qlplugindir:          "~/Library/QuickLook",
        mdimporterdir:        "~/Library/Spotlight",
        dictionarydir:        "~/Library/Dictionaries",
        fontdir:              "~/Library/Fonts",
        servicedir:           "~/Library/Services",
        input_methoddir:      "~/Library/Input Methods",
        internet_plugindir:   "~/Library/Internet Plug-Ins",
        audio_unit_plugindir: "~/Library/Audio/Plug-Ins/Components",
        vst_plugindir:        "~/Library/Audio/Plug-Ins/VST",
        vst3_plugindir:       "~/Library/Audio/Plug-Ins/VST3",
        screen_saverdir:      "~/Library/Screen Savers",
      }.freeze,
      T::Hash[Symbol, String],
    )

    # runtime recursive evaluation forces the LazyObject to be evaluated
    T::Sig::WithoutRuntime.sig { returns(ConfigHash) }
    def self.defaults
      {
        languages: T.let([], T::Array[String]),
      }.merge(DEFAULT_DIRS).freeze
    end

    sig { params(args: Homebrew::CLI::Args).returns(T.attached_class) }
    def self.from_args(args)
      # The option methods are only defined on `args` when `cask_options` is invoked on the parser.
      explicit = [*DEFAULT_DIRS.keys, :language].to_h do |option|
        [option, (args.public_send(option) if args.respond_to?(option))]
      end
      explicit[:languages] = explicit.delete(:language)
      new(explicit: explicit.compact)
    end

    sig { params(json: String, ignore_invalid_keys: T::Boolean).returns(T.attached_class) }
    def self.from_json(json, ignore_invalid_keys: false)
      config = JSON.parse(json, symbolize_names: true)

      new(
        default:             reject_legacy_keys(config.fetch(:default,  {})),
        env:                 reject_legacy_keys(config.fetch(:env,      {})),
        explicit:            reject_legacy_keys(config.fetch(:explicit, {})) || {},
        ignore_invalid_keys:,
      )
    end

    # Saved configs can contain hyphenated option names that were never honored when read back,
    # so drop them instead of warning about them or retroactively making them take effect.
    sig { params(config: T.nilable(ConfigHash)).returns(T.nilable(ConfigHash)) }
    def self.reject_legacy_keys(config)
      return if config.nil?

      valid_keys = defaults
      config.reject { |key, _| key.to_s.include?("-") && valid_keys.key?(key.to_s.tr("-", "_").to_sym) }
    end

    # runtime recursive evaluation forces the LazyObject to be evaluated
    T::Sig::WithoutRuntime.sig { params(config: ConfigHash).returns(ConfigHash) }
    def self.canonicalize(config)
      config.to_h do |k, v|
        if DEFAULT_DIRS.key?(k)
          raise TypeError, "Invalid path for default dir #{k}: #{v.inspect}" if v.is_a?(Array)

          [k, Pathname(v.to_s).expand_path]
        else
          [k, v]
        end
      end
    end

    # Get the explicit configuration.
    #
    # @api internal
    sig { returns(ConfigHash) }
    attr_accessor :explicit

    sig {
      params(
        default:             T.nilable(ConfigHash),
        env:                 T.nilable(ConfigHash),
        explicit:            ConfigHash,
        ignore_invalid_keys: T::Boolean,
      ).void
    }
    def initialize(default: nil, env: nil, explicit: {}, ignore_invalid_keys: false)
      # Define all instance variables in a consistent order so every instance
      # shares one object shape, avoiding Ruby's shape-variation warning.
      @default = T.let(
        default ? self.class.canonicalize(self.class.defaults.merge(default)) : nil,
        T.nilable(ConfigHash),
      )
      @env = T.let(
        env ? self.class.canonicalize(env) : nil,
        T.nilable(ConfigHash),
      )
      @explicit = T.let(
        self.class.canonicalize(explicit),
        ConfigHash,
      )
      @binarydir = T.let(nil, T.nilable(Pathname))
      @manpagedir = T.let(nil, T.nilable(Pathname))
      @bash_completion = T.let(nil, T.nilable(Pathname))
      @zsh_completion = T.let(nil, T.nilable(Pathname))
      @fish_completion = T.let(nil, T.nilable(Pathname))
      @pwsh_completion = T.let(nil, T.nilable(Pathname))

      if ignore_invalid_keys &&
         (unknown_keys = ((Array(@env&.keys) + @explicit.keys).uniq - self.class.defaults.keys).presence)
        opoo "Ignoring unknown cask configuration keys: #{unknown_keys.inspect}"

        @env&.delete_if { |key, _| unknown_keys.include?(key) }
        @explicit.delete_if { |key, _| unknown_keys.include?(key) }
        return
      end

      ::Utils::Data.assert_valid_keys(@env, *self.class.defaults.keys) if @env
      ::Utils::Data.assert_valid_keys(@explicit, *self.class.defaults.keys)
    end

    # runtime recursive evaluation forces the LazyObject to be evaluated
    T::Sig::WithoutRuntime.sig { returns(ConfigHash) }
    def default
      @default ||= self.class.canonicalize(self.class.defaults)
    end

    sig { returns(ConfigHash) }
    def env
      @env ||= self.class.canonicalize(
        Homebrew::EnvConfig.cask_opts
          .select { |arg| arg.include?("=") }
          .map { |arg| T.cast(arg.split("=", 2), [String, String]) }
          .to_h do |(flag, value)|
            # command-line flags are hyphenated (e.g. --input-methoddir) but config keys use underscores
            key = flag.sub(/^--/, "").tr("-", "_")
            # converts --language flag to :languages config key
            if key == "language"
              key = "languages"
              value = value.split(",")
            end

            [key.to_sym, value]
          end,
      )
    end

    sig { returns(Pathname) }
    def binarydir
      @binarydir ||= HOMEBREW_PREFIX/"bin"
    end

    sig { returns(Pathname) }
    def manpagedir
      @manpagedir ||= HOMEBREW_PREFIX/"share/man"
    end

    sig { returns(Pathname) }
    def bash_completion
      @bash_completion ||= HOMEBREW_PREFIX/"etc/bash_completion.d"
    end

    sig { returns(Pathname) }
    def zsh_completion
      @zsh_completion ||= HOMEBREW_PREFIX/"share/zsh/site-functions"
    end

    sig { returns(Pathname) }
    def fish_completion
      @fish_completion ||= HOMEBREW_PREFIX/"share/fish/vendor_completions.d"
    end

    sig { returns(Pathname) }
    def pwsh_completion
      @pwsh_completion ||= HOMEBREW_PREFIX/"share/pwsh/completions"
    end

    sig { returns(T::Array[String]) }
    def languages
      [
        *explicit.fetch(:languages, []),
        *env.fetch(:languages, []),
        *default.fetch(:languages, []),
      ].uniq.select do |lang|
        # Ensure all languages are valid.
        Locale.parse(lang)
        true
      rescue Locale::ParserError
        false
      end
    end

    sig { params(languages: T::Array[String]).void }
    def languages=(languages)
      explicit[:languages] = languages
    end

    DEFAULT_DIRS.each_key do |dir|
      define_method(dir) do
        T.bind(self, Config)
        explicit.fetch(dir, env.fetch(dir, default.fetch(dir)))
      end

      define_method(:"#{dir}=") do |path|
        T.bind(self, Config)
        explicit[dir] = Pathname(path).expand_path
      end
    end

    sig { params(other: Config).returns(T.self_type) }
    def merge(other)
      self.class.new(explicit: other.explicit.merge(explicit))
    end

    sig { params(options: T.untyped).returns(String) }
    def to_json(*options)
      {
        default:,
        env:,
        explicit:,
      }.to_json(*options)
    end
  end
end

require "extend/os/cask/config"
