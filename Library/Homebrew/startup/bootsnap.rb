# typed: true
# frozen_string_literal: true

module Homebrew
  module Bootsnap
    def self.key
      @key ||= begin
        require "digest/sha2"

        checksum = Digest::SHA256.new
        checksum << RUBY_VERSION
        checksum << RUBY_PLATFORM
        checksum << Dir.children(File.join(Gem.paths.path, "gems")).join(",")

        checksum.hexdigest
      end
    end

    private_class_method def self.cache_dir
      cache = ENV.fetch("HOMEBREW_CACHE", nil) || ENV.fetch("HOMEBREW_DEFAULT_CACHE", nil)
      raise "Needs `$HOMEBREW_CACHE` or `$HOMEBREW_DEFAULT_CACHE`!" if cache.nil? || cache.empty?

      File.join(cache, "bootsnap", key)
    end

    private_class_method def self.ignore_directories
      # We never do `require "vendor/bundle/ruby/..."` or `require "vendor/portable-ruby/..."`,
      # so let's slim the cache a bit by excluding them.
      # Note that gems within `bundle/ruby` will still be cached - these are when directory walking down from above.
      [
        (HOMEBREW_LIBRARY_PATH/"vendor/bundle/ruby").to_s,
        (HOMEBREW_LIBRARY_PATH/"vendor/portable-ruby").to_s,
      ]
    end

    private_class_method def self.enabled?
      !ENV["HOMEBREW_BOOTSNAP_GEM_PATH"].to_s.empty? && ENV["HOMEBREW_NO_BOOTSNAP"].nil?
    end

    def self.load!(compile_cache: true)
      return unless enabled?

      require ENV.fetch("HOMEBREW_BOOTSNAP_GEM_PATH")

      ::Bootsnap.setup(
        cache_dir:,
        ignore_directories:,
        # In development environments the bootsnap compilation cache is
        # generated on the fly when source files are loaded.
        # https://github.com/Shopify/bootsnap?tab=readme-ov-file#precompilation
        development_mode:   true,
        load_path_cache:    true,
        compile_cache_iseq: compile_cache,
        compile_cache_yaml: compile_cache,
      )
    end

    def self.reset!
      return unless enabled?

      ::Bootsnap.unload_cache!
      @key = nil

      # The compile cache doesn't get unloaded so we don't need to load it again!
      load!(compile_cache: false)
    end
  end
end

Homebrew::Bootsnap.load!
