# typed: strict
# frozen_string_literal: true

require "json"

require "lazy_object"
require "locale"
require "extend/hash/keys"

module Cask
  # Configuration for installing casks.
  #
  # @api internal
  class Config
    DEFAULT_DIRS = T.let(
      {
        appdir:               "/Applications",
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

    sig { returns(T::Hash[Symbol, String]) }
    def self.defaults
      {
        languages: LazyObject.new { ::OS::Mac.languages },
      }.merge(DEFAULT_DIRS).freeze
    end

    sig { params(args: Homebrew::CLI::Args).returns(T.attached_class) }
    def self.from_args(args)
      # FIXME: T.unsafe is a workaround for methods that are only defined when `cask_options`
      # is invoked on the parser. (These could be captured by a DSL compiler instead.)
      args = T.unsafe(args)
      new(explicit: {
        appdir:               args.appdir,
        keyboard_layoutdir:   args.keyboard_layoutdir,
        colorpickerdir:       args.colorpickerdir,
        prefpanedir:          args.prefpanedir,
        qlplugindir:          args.qlplugindir,
        mdimporterdir:        args.mdimporterdir,
        dictionarydir:        args.dictionarydir,
        fontdir:              args.fontdir,
        servicedir:           args.servicedir,
        input_methoddir:      args.input_methoddir,
        internet_plugindir:   args.internet_plugindir,
        audio_unit_plugindir: args.audio_unit_plugindir,
        vst_plugindir:        args.vst_plugindir,
        vst3_plugindir:       args.vst3_plugindir,
        screen_saverdir:      args.screen_saverdir,
        languages:            args.language,
      }.compact)
    end

    sig { params(json: String, ignore_invalid_keys: T::Boolean).returns(T.attached_class) }
    def self.from_json(json, ignore_invalid_keys: false)
      config = JSON.parse(json)

      new(
        default:             config.fetch("default",  {}),
        env:                 config.fetch("env",      {}),
        explicit:            config.fetch("explicit", {}),
        ignore_invalid_keys:,
      )
    end

    sig {
      params(
        config: T::Enumerable[
          [T.any(String, Symbol), T.any(String, Pathname, T::Array[String])],
        ],
      ).returns(
        T::Hash[Symbol, T.any(String, Pathname, T::Array[String])],
      )
    }
    def self.canonicalize(config)
      config.to_h do |k, v|
        key = k.to_sym

        if DEFAULT_DIRS.key?(key)
          raise TypeError, "Invalid path for default dir #{k}: #{v.inspect}" if v.is_a?(Array)

          [key, Pathname(v).expand_path]
        else
          [key, v]
        end
      end
    end

    # Get the explicit configuration.
    #
    # @api internal
    sig { returns(T::Hash[Symbol, T.any(String, Pathname, T::Array[String])]) }
    attr_accessor :explicit

    sig {
      params(
        default:             T.nilable(T::Hash[Symbol, T.any(String, Pathname, T::Array[String])]),
        env:                 T.nilable(T::Hash[Symbol, T.any(String, Pathname, T::Array[String])]),
        explicit:            T::Hash[Symbol, T.any(String, Pathname, T::Array[String])],
        ignore_invalid_keys: T::Boolean,
      ).void
    }
    def initialize(default: nil, env: nil, explicit: {}, ignore_invalid_keys: false)
      if default
        @default = T.let(
          self.class.canonicalize(self.class.defaults.merge(default)),
          T.nilable(T::Hash[Symbol, T.any(String, Pathname, T::Array[String])]),
        )
      end
      if env
        @env = T.let(
          self.class.canonicalize(env),
          T.nilable(T::Hash[Symbol, T.any(String, Pathname, T::Array[String])]),
        )
      end
      @explicit = T.let(
        self.class.canonicalize(explicit),
        T::Hash[Symbol, T.any(String, Pathname, T::Array[String])],
      )

      if ignore_invalid_keys
        @env&.delete_if { |key, _| self.class.defaults.keys.exclude?(key) }
        @explicit.delete_if { |key, _| self.class.defaults.keys.exclude?(key) }
        return
      end

      @env&.assert_valid_keys(*self.class.defaults.keys)
      @explicit.assert_valid_keys(*self.class.defaults.keys)
    end

    sig { returns(T::Hash[Symbol, T.any(String, Pathname, T::Array[String])]) }
    def default
      @default ||= self.class.canonicalize(self.class.defaults)
    end

    sig { returns(T::Hash[Symbol, T.any(String, Pathname, T::Array[String])]) }
    def env
      @env ||= self.class.canonicalize(
        Homebrew::EnvConfig.cask_opts
          .select { |arg| arg.include?("=") }
          .map { |arg| T.cast(arg.split("=", 2), [String, String]) }
          .map do |(flag, value)|
            key = flag.sub(/^--/, "")
            # converts --language flag to :languages config key
            if key == "language"
              key = "languages"
              value = value.split(",")
            end

            [key, value]
          end,
      )
    end

    sig { returns(Pathname) }
    def binarydir
      @binarydir ||= T.let(HOMEBREW_PREFIX/"bin", T.nilable(Pathname))
    end

    sig { returns(Pathname) }
    def manpagedir
      @manpagedir ||= T.let(HOMEBREW_PREFIX/"share/man", T.nilable(Pathname))
    end

    sig { returns(Pathname) }
    def bash_completion
      @bash_completion ||= T.let(HOMEBREW_PREFIX/"etc/bash_completion.d", T.nilable(Pathname))
    end

    sig { returns(Pathname) }
    def zsh_completion
      @zsh_completion ||= T.let(HOMEBREW_PREFIX/"share/zsh/site-functions", T.nilable(Pathname))
    end

    sig { returns(Pathname) }
    def fish_completion
      @fish_completion ||= T.let(HOMEBREW_PREFIX/"share/fish/vendor_completions.d", T.nilable(Pathname))
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
