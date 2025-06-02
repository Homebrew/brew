# frozen_string_literal: true

module Bootsnap
  module LoadPathCache
    FALLBACK_SCAN = BasicObject.new

    DOT_RB = ".rb"
    DOT_SO = ".so"
    SLASH  = "/"

    DL_EXTENSIONS = ::RbConfig::CONFIG
      .values_at("DLEXT", "DLEXT2")
      .reject { |ext| !ext || ext.empty? }
      .map    { |ext| ".#{ext}" }
      .freeze
    DLEXT = DL_EXTENSIONS[0]
    # This is nil on linux and darwin, but I think it's '.o' on some other
    # platform.  I'm not really sure which, but it seems better to replicate
    # ruby's semantics as faithfully as possible.
    DLEXT2 = DL_EXTENSIONS[1]

    CACHED_EXTENSIONS = DLEXT2 ? [DOT_RB, DLEXT, DLEXT2] : [DOT_RB, DLEXT]

    @enabled = false

    class << self
      attr_reader(:load_path_cache, :loaded_features_index, :enabled)
      alias_method :enabled?, :enabled
      remove_method(:enabled)

      def setup(cache_path:, development_mode:, ignore_directories:, readonly: false)
        unless supported?
          warn("[bootsnap/setup] Load path caching is not supported on this implementation of Ruby") if $VERBOSE
          return
        end

        store = Store.new(cache_path, readonly: readonly)

        @loaded_features_index = LoadedFeaturesIndex.new

        PathScanner.ignored_directories = ignore_directories if ignore_directories
        @load_path_cache = Cache.new(store, $LOAD_PATH, development_mode: development_mode)
        @enabled = true
        require_relative "load_path_cache/core_ext/kernel_require"
        require_relative "load_path_cache/core_ext/loaded_features"
      end

      def unload!
        @enabled = false
        @loaded_features_index = nil
        @realpath_cache = nil
        @load_path_cache = nil
        ChangeObserver.unregister($LOAD_PATH) if supported?
      end

      def supported?
        if RUBY_PLATFORM.match?(/darwin|linux|bsd|mswin|mingw|cygwin/)
          case RUBY_ENGINE
          when "truffleruby"
            # https://github.com/oracle/truffleruby/issues/3131
            RUBY_ENGINE_VERSION >= "23.1.0"
          when "ruby"
            true
          else
            false
          end
        end
      end
    end
  end
end

if Bootsnap::LoadPathCache.supported?
  require_relative "load_path_cache/path_scanner"
  require_relative "load_path_cache/path"
  require_relative "load_path_cache/cache"
  require_relative "load_path_cache/store"
  require_relative "load_path_cache/change_observer"
  require_relative "load_path_cache/loaded_features_index"
end
