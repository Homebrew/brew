# typed: strict
# frozen_string_literal: true

module Homebrew
  # Caches of the language package managers used by sandboxed fetch, build,
  # test and postinstall phases, shared between formula builds.
  module PackageManagerCache
    DIRECTORIES = %w[
      bundler_cache
      cabal_cache
      cargo_cache
      composer_cache
      gclient_cache
      gem_cache
      glide_home
      go_cache
      go_mod_cache
      hex_cache
      java_cache
      npm_cache
      nuget_cache
      pip_cache
      pnpm_cache
      uv_cache
      yarn_cache
      zig_cache
    ].freeze

    # Caches whose package managers verify content hashes on every read, so
    # tampered or stale entries are rejected rather than used. These are safe
    # to keep between builds.
    CONTENT_ADDRESSED_DIRECTORIES = %w[
      npm_cache
      pnpm_cache
    ].freeze

    sig { params(name: String).returns(Pathname) }
    def self.path(name)
      raise ArgumentError, "Unknown package manager cache: #{name}" unless DIRECTORIES.include?(name)

      HOMEBREW_CACHE/name
    end

    sig { returns(T::Array[Pathname]) }
    def self.paths = DIRECTORIES.map { |name| path(name) }

    sig { returns(T::Hash[Symbol, String]) }
    def self.env
      {
        _JAVA_OPTIONS:           "-Duser.home=#{path("java_cache")}",
        BUNDLE_GLOBAL_GEM_CACHE: "true",
        BUNDLE_USER_CACHE:       path("bundler_cache").to_s,
        CABAL_DIR:               path("cabal_cache").to_s,
        CARGO_HOME:              path("cargo_cache").to_s,
        COMPOSER_CACHE_DIR:      path("composer_cache").to_s,
        GEM_SPEC_CACHE:          path("gem_cache").to_s,
        GOCACHE:                 path("go_cache").to_s,
        GOPATH:                  path("go_mod_cache").to_s,
        HEX_HOME:                path("hex_cache").to_s,
        NPM_CONFIG_CACHE:        path("npm_cache").to_s,
        NPM_CONFIG_STORE_DIR:    path("pnpm_cache").to_s,
        NUGET_PACKAGES:          path("nuget_cache").to_s,
        PIP_CACHE_DIR:           path("pip_cache").to_s,
        UV_CACHE_DIR:            path("uv_cache").to_s,
        YARN_CACHE_FOLDER:       path("yarn_cache").to_s,
        ZIG_GLOBAL_CACHE_DIR:    path("zig_cache").to_s,
      }
    end
  end
end
