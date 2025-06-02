# frozen_string_literal: true

module Bootsnap
  module CompileCache
    UNCOMPILABLE = BasicObject.new
    def UNCOMPILABLE.inspect
      "<Bootsnap::UNCOMPILABLE>"
    end

    Error = Class.new(StandardError)

    def self.setup(cache_dir:, iseq:, yaml:, json:, readonly: false, revalidation: false)
      if iseq
        if supported?
          require_relative "compile_cache/iseq"
          Bootsnap::CompileCache::ISeq.install!(cache_dir)
        elsif $VERBOSE
          warn("[bootsnap/setup] bytecode caching is not supported on this implementation of Ruby")
        end
      end

      if yaml
        if supported?
          require_relative "compile_cache/yaml"
          Bootsnap::CompileCache::YAML.install!(cache_dir)
        elsif $VERBOSE
          warn("[bootsnap/setup] YAML parsing caching is not supported on this implementation of Ruby")
        end
      end

      if json
        if supported?
          require_relative "compile_cache/json"
          Bootsnap::CompileCache::JSON.install!(cache_dir)
        elsif $VERBOSE
          warn("[bootsnap/setup] JSON parsing caching is not supported on this implementation of Ruby")
        end
      end

      if supported? && defined?(Bootsnap::CompileCache::Native)
        Bootsnap::CompileCache::Native.readonly = readonly
        Bootsnap::CompileCache::Native.revalidation = revalidation
      end
    end

    def self.supported?
      # only enable on 'ruby' (MRI) and TruffleRuby for POSIX (darwin, linux, *bsd), Windows (RubyInstaller2)
      %w[ruby truffleruby].include?(RUBY_ENGINE) &&
        RUBY_PLATFORM.match?(/darwin|linux|bsd|mswin|mingw|cygwin/)
    end
  end
end
