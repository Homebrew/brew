# frozen_string_literal: true

require_relative "bootsnap/version"
require_relative "bootsnap/bundler"
require_relative "bootsnap/load_path_cache"
require_relative "bootsnap/compile_cache"

module Bootsnap
  InvalidConfiguration = Class.new(StandardError)

  class << self
    attr_reader :logger

    def log_stats!
      stats = {hit: 0, revalidated: 0, miss: 0, stale: 0}
      self.instrumentation = ->(event, _path) { stats[event] += 1 }
      Kernel.at_exit do
        stats.each do |event, count|
          $stderr.puts "bootsnap #{event}: #{count}"
        end
      end
    end

    def log!
      self.logger = $stderr.method(:puts)
    end

    def logger=(logger)
      @logger = logger
      self.instrumentation = if logger.respond_to?(:debug)
        ->(event, path) { @logger.debug("[Bootsnap] #{event} #{path}") unless event == :hit }
      else
        ->(event, path) { @logger.call("[Bootsnap] #{event} #{path}") unless event == :hit }
      end
    end

    def instrumentation=(callback)
      @instrumentation = callback
      if respond_to?(:instrumentation_enabled=, true)
        self.instrumentation_enabled = !!callback
      end
    end

    def _instrument(event, path)
      @instrumentation.call(event, path)
    end

    def setup(
      cache_dir:,
      development_mode: true,
      load_path_cache: true,
      ignore_directories: nil,
      readonly: false,
      revalidation: false,
      compile_cache_iseq: true,
      compile_cache_yaml: true,
      compile_cache_json: true
    )
      if load_path_cache
        Bootsnap::LoadPathCache.setup(
          cache_path: "#{cache_dir}/bootsnap/load-path-cache",
          development_mode: development_mode,
          ignore_directories: ignore_directories,
          readonly: readonly,
        )
      end

      Bootsnap::CompileCache.setup(
        cache_dir: "#{cache_dir}/bootsnap/compile-cache",
        iseq: compile_cache_iseq,
        yaml: compile_cache_yaml,
        json: compile_cache_json,
        readonly: readonly,
        revalidation: revalidation,
      )
    end

    def unload_cache!
      LoadPathCache.unload!
    end

    def default_setup
      env = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || ENV["ENV"]
      development_mode = ["", nil, "development"].include?(env)

      if enabled?("BOOTSNAP")
        cache_dir = ENV["BOOTSNAP_CACHE_DIR"]
        unless cache_dir
          config_dir_frame = caller.detect do |line|
            line.include?("/config/")
          end

          unless config_dir_frame
            $stderr.puts("[bootsnap/setup] couldn't infer cache directory! Either:")
            $stderr.puts("[bootsnap/setup]   1. require bootsnap/setup from your application's config directory; or")
            $stderr.puts("[bootsnap/setup]   2. Define the environment variable BOOTSNAP_CACHE_DIR")

            raise("couldn't infer bootsnap cache directory")
          end

          path = config_dir_frame.split(/:\d+:/).first
          path = File.dirname(path) until File.basename(path) == "config"
          app_root = File.dirname(path)

          cache_dir = File.join(app_root, "tmp", "cache")
        end

        ignore_directories = if ENV.key?("BOOTSNAP_IGNORE_DIRECTORIES")
          ENV["BOOTSNAP_IGNORE_DIRECTORIES"].split(",")
        end

        setup(
          cache_dir: cache_dir,
          development_mode: development_mode,
          load_path_cache: enabled?("BOOTSNAP_LOAD_PATH_CACHE"),
          compile_cache_iseq: enabled?("BOOTSNAP_COMPILE_CACHE"),
          compile_cache_yaml: enabled?("BOOTSNAP_COMPILE_CACHE"),
          compile_cache_json: enabled?("BOOTSNAP_COMPILE_CACHE"),
          readonly: bool_env("BOOTSNAP_READONLY"),
          revalidation: bool_env("BOOTSNAP_REVALIDATE"),
          ignore_directories: ignore_directories,
        )

        if ENV["BOOTSNAP_LOG"]
          log!
        elsif ENV["BOOTSNAP_STATS"]
          log_stats!
        end
      end
    end

    if RbConfig::CONFIG["host_os"] =~ /mswin|mingw|cygwin/
      def absolute_path?(path)
        path[1] == ":"
      end
    else
      def absolute_path?(path)
        path.start_with?("/")
      end
    end

    # This is a semi-accurate ruby implementation of the native `rb_get_path(VALUE)` function.
    # The native version is very intricate and may behave differently on windows etc.
    # But we only use it for non-MRI platform.
    def rb_get_path(fname)
      path_path = fname.respond_to?(:to_path) ? fname.to_path : fname
      String.try_convert(path_path) || raise(TypeError, "no implicit conversion of #{path_path.class} into String")
    end

    # Allow the C extension to redefine `rb_get_path` without warning.
    alias_method :rb_get_path, :rb_get_path # rubocop:disable Lint/DuplicateMethods

    private

    def enabled?(key)
      !ENV["DISABLE_#{key}"]
    end

    def bool_env(key, default: false)
      value = ENV.fetch(key) { default }
      !["0", "false", false].include?(value)
    end
  end
end
