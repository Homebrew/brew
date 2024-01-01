# typed: true
# frozen_string_literal: true

# Disable Rails cops, as we haven't required active_support yet.
# rubocop:disable Rails
homebrew_bootsnap_enabled = ENV["HOMEBREW_NO_BOOTSNAP"].nil? && !ENV["HOMEBREW_BOOTSNAP"].nil?

# we need some development tools to build bootsnap native code
homebrew_bootsnap_enabled &&= if ENV["HOMEBREW_MACOS_VERSION"]
  File.directory?("/Applications/Xcode.app") || File.directory?("/Library/Developer/CommandLineTools")
else
  File.executable?("/usr/bin/clang") || File.executable?("/usr/bin/gcc")
end

if homebrew_bootsnap_enabled
  begin
    require "bootsnap"
  rescue LoadError
    unless ENV["HOMEBREW_BOOTSNAP_RETRY"]
      Homebrew.install_bundler_gems!(groups: ["bootsnap"], only_warn_on_failure: true)

      ENV["HOMEBREW_BOOTSNAP_RETRY"] = "1"
      exec ENV.fetch("HOMEBREW_BREW_FILE"), *ARGV
    end
  end

  ENV.delete("HOMEBREW_BOOTSNAP_RETRY")

  if defined?(Bootsnap)
    cache = ENV.fetch("HOMEBREW_CACHE", nil) || ENV.fetch("HOMEBREW_DEFAULT_CACHE", nil)
    raise "Needs HOMEBREW_CACHE or HOMEBREW_DEFAULT_CACHE!" if cache.nil? || cache.empty?

    # We never do `require "vendor/bundle/ruby/..."` or `require "vendor/portable-ruby/..."`,
    # so let's slim the cache a bit by excluding them.
    # Note that gems within `bundle/ruby` will still be cached - these are when directory walking down from above.
    ignore_directories = [
      (HOMEBREW_LIBRARY_PATH/"vendor/bundle/ruby").to_s,
      (HOMEBREW_LIBRARY_PATH/"vendor/portable-ruby").to_s,
    ]

    Bootsnap.setup(
      cache_dir:          cache,
      ignore_directories: ignore_directories,
      load_path_cache:    true,
      compile_cache_iseq: true,
      compile_cache_yaml: true,
    )
  else
    $stderr.puts "Error: HOMEBREW_BOOTSNAP could not `require \"bootsnap\"`!\n\n"
  end
end
# rubocop:enable Rails
