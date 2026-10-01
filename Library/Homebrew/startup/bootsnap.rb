# typed: true
# frozen_string_literal: true

module Homebrew
  module Bootsnap
    # This is the default Bundler group and its transitive dependencies. Optional
    # groups must not rotate the compile cache used by the core load graph.
    CORE_GEM_NAMES = %w[
      bindata
      concurrent-ruby
      elftools
      logger
      patchelf
      plist
      ruby-macho
      sorbet-runtime
    ].freeze
    private_constant :CORE_GEM_NAMES

    def self.core_gem_names = CORE_GEM_NAMES

    private_class_method def self.gem_directories
      Dir.children(File.join(Gem.paths.path, "gems")).sort
    end

    def self.key
      @key ||= begin
        require "digest/sha2"

        checksum = Digest::SHA256.new
        checksum << RUBY_VERSION
        checksum << RUBY_PLATFORM
        checksum << gem_directories
                    .select { |gem| core_gem_names.any? { |name| gem.start_with?("#{name}-") } }
                    .join(",")

        checksum.hexdigest
      end
    end

    private_class_method def self.cache_dir
      cache = ENV.fetch("HOMEBREW_CACHE", nil) || ENV.fetch("HOMEBREW_DEFAULT_CACHE", nil)
      raise "Needs `$HOMEBREW_CACHE` or `$HOMEBREW_DEFAULT_CACHE`!" if cache.nil? || cache.empty?

      File.join(cache, "bootsnap", key)
    end

    private_class_method def self.load_path_cache
      File.join(cache_dir, "bootsnap/load-path-cache")
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

      begin
        require ENV.fetch("HOMEBREW_BOOTSNAP_GEM_PATH")
      rescue LoadError
        return
      end

      installed_gem_directories = gem_directories.join(",")
      gem_directories_cache = File.join(cache_dir, "bootsnap/gem-directories")
      if !File.exist?(gem_directories_cache) || File.read(gem_directories_cache) != installed_gem_directories
        # The compile cache is shared across optional groups, but Bootsnap treats
        # gem load paths as immutable, so invalidate their separate index.
        require "fileutils"
        FileUtils.rm_f load_path_cache
        FileUtils.mkdir_p File.dirname(gem_directories_cache)
        File.write(gem_directories_cache, installed_gem_directories)
      end

      ::Bootsnap.setup(
        cache_dir:,
        ignore_directories:,
        # In development environments the bootsnap compilation cache is
        # generated on the fly when source files are loaded.
        # https://github.com/Shopify/bootsnap?tab=readme-ov-file#precompilation
        development_mode:   true,
        load_path_cache:    true,
        # Ruby refuses InstructionSequence#to_binary while Coverage is active.
        compile_cache_iseq: compile_cache && ENV["HOMEBREW_TESTS_COVERAGE"].nil?,
        compile_cache_yaml: compile_cache,
      )
    end

    def self.reset!
      return unless enabled?

      ::Bootsnap.unload_cache!
      # Gem changes invalidate resolution, but compiled files validate themselves
      # against their source contents, so only discard the persisted load path.
      require "fileutils"
      FileUtils.rm_f load_path_cache
      @key = nil

      load!(compile_cache: false)
    end

    # Compile caches for the load graphs of common commands in a detached
    # background process, so the next `brew` command doesn't pay the cost of
    # compiling caches for Ruby files changed by e.g. `brew update`.
    def self.prewarm!
      return unless enabled?
      return if ENV["HOMEBREW_TESTS"]

      pid = Process.spawn(
        *HOMEBREW_RUBY_EXEC_ARGS,
        "-I", $LOAD_PATH.join(File::PATH_SEPARATOR),
        "-rglobal", "-rcmd/install", "-rcmd/fetch", "-rcmd/upgrade",
        "-e", "",
        in: File::NULL, out: File::NULL, err: File::NULL, pgroup: true
      )
      Process.detach(pid)
    rescue SystemCallError
      nil
    end
  end
end

Homebrew::Bootsnap.load!
