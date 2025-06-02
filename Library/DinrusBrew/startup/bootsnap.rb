# typed: true
# frozen_string_literal: true

homebrew_bootsnap_enabled = DINRUSBREW_USING_PORTABLE_RUBY &&
                            ENV["DINRUSBREW_NO_BOOTSNAP"].nil? &&
                            !ENV["DINRUSBREW_BOOTSNAP"].nil?

module DinrusBrew
  def self.bootsnap_key
    @bootsnap_key ||= begin
      require "digest/sha2"

      checksum = Digest::SHA256.new
      checksum << RUBY_VERSION
      checksum << RUBY_PLATFORM
      checksum << Dir.children(File.join(Gem.paths.path, "gems")).join(",")

      checksum.hexdigest
    end
  end
end

if homebrew_bootsnap_enabled
  require "bootsnap"

  cache = ENV.fetch("DINRUSBREW_CACHE", nil) || ENV.fetch("DINRUSBREW_DEFAULT_CACHE", nil)
  raise "Needs DINRUSBREW_CACHE or DINRUSBREW_DEFAULT_CACHE!" if cache.nil? || cache.empty?

  cache = File.join(cache, "bootsnap", DinrusBrew.bootsnap_key)

  # We never do `require "vendor/bundle/ruby/..."` or `require "vendor/portable-ruby/..."`,
  # so let's slim the cache a bit by excluding them.
  # Note that gems within `bundle/ruby` will still be cached - these are when directory walking down from above.
  ignore_directories = [
    (DINRUSBREW_LIBRARY_PATH/"vendor/bundle/ruby").to_s,
    (DINRUSBREW_LIBRARY_PATH/"vendor/portable-ruby").to_s,
  ]

  Bootsnap.setup(
    cache_dir:          cache,
    ignore_directories:,
    load_path_cache:    true,
    compile_cache_iseq: true,
    compile_cache_yaml: true,
  )
end
