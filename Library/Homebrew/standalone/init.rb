# typed: true
# frozen_string_literal: true

# This file is included before any other files.
# It intentionally has typing disabled and uses `Homebrew::FastBootRequire`
# or `require_relative` to load all files
# (except "rbconfig" which is needed by `Homebrew::FastBootRequire`)

required_ruby_major, required_ruby_minor, = ENV.fetch("HOMEBREW_REQUIRED_RUBY_VERSION", "").split(".").map(&:to_i)
gems_vendored = if required_ruby_minor.nil?
  # We're likely here if running RuboCop etc, so just assume we don't need to install gems as we likely already have
  true
else
  ruby_major, ruby_minor, = RUBY_VERSION.split(".").map(&:to_i)
  raise "Could not parse Ruby requirements" if !ruby_major || !ruby_minor || !required_ruby_major

  if ruby_major < required_ruby_major || (ruby_major == required_ruby_major && ruby_minor < required_ruby_minor)
    raise "Homebrew must be run under Ruby #{required_ruby_major}.#{required_ruby_minor}! " \
          "You're running #{RUBY_VERSION}."
  end

  # This list should match .gitignore
  vendored_versions = ["3.4"].freeze
  vendored_versions.include?("#{ruby_major}.#{ruby_minor}")
end.freeze

if ENV["HOMEBREW_DEVELOPER"]
  Warning.categories.each do |category|
    Warning[category] = true
  end
end

# Setup Homebrew::FastBootRequire for faster boot requires.
# Inspired by https://github.com/Shopify/bootsnap/wiki/Bootlib::Require
require "rbconfig"

module Homebrew
  module FastBootRequire
    ARCHDIR    = RbConfig::CONFIG["archdir"].freeze
    RUBYLIBDIR = RbConfig::CONFIG["rubylibdir"].freeze

    def self.from_archdir(feature)
      require(File.join(ARCHDIR, feature.to_s))
    end

    def self.from_rubylibdir(feature)
      require(File.join(RUBYLIBDIR, "#{feature}.rb"))
    end
  end
end

# We trust base Ruby to provide what we need.
# Don't look into the user-installed sitedir, which may contain older versions of RubyGems.
$LOAD_PATH.reject! { |path| path.start_with?(RbConfig::CONFIG["sitedir"]) }

Homebrew::FastBootRequire.from_rubylibdir("pathname")
dir = __dir__ || raise("__dir__ is not defined")
HOMEBREW_LIBRARY_PATH = Pathname(dir).parent.realpath.freeze
HOMEBREW_USING_PORTABLE_RUBY = RbConfig.ruby.include?("/vendor/portable-ruby/").freeze

HOMEBREW_BUNDLER_VERSION = ENV.fetch("HOMEBREW_BUNDLER_VERSION").freeze
ENV["BUNDLER_VERSION"] = HOMEBREW_BUNDLER_VERSION

require_relative "../utils/gems"
Homebrew.setup_gem_environment!(setup_path: false)

# Install gems for Rubies we don't vendor for.
if !gems_vendored && !ENV["HOMEBREW_SKIP_INITIAL_GEM_INSTALL"]
  Homebrew.install_bundler_gems!(setup_path: false)
  ENV["HOMEBREW_SKIP_INITIAL_GEM_INSTALL"] = "1"
end

unless $LOAD_PATH.include?(HOMEBREW_LIBRARY_PATH.to_s)
  # Insert the path after any existing Homebrew paths (e.g. those inserted by tests and parent processes)
  last_homebrew_path_idx = $LOAD_PATH.rindex do |path|
    path.start_with?(HOMEBREW_LIBRARY_PATH.to_s) && !path.include?("vendor/portable-ruby")
  end || -1
  $LOAD_PATH.insert(last_homebrew_path_idx + 1, HOMEBREW_LIBRARY_PATH.to_s)
end
require_relative "../vendor/bundle/bundler/setup"
Homebrew::FastBootRequire.from_archdir("portable_ruby_gems") if HOMEBREW_USING_PORTABLE_RUBY
$LOAD_PATH.unshift "#{HOMEBREW_LIBRARY_PATH}/vendor/bundle/#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/" \
                   "bundler-#{HOMEBREW_BUNDLER_VERSION}/lib"
$LOAD_PATH.uniq!

# These warnings are nice but often flag problems that are not even our responsibly,
# including in some cases from other Ruby standard library gems.
# We strictly only allow one version of Ruby at a time so future compatibility
# doesn't need to be handled ahead of time.
if defined?(Gem::BUNDLED_GEMS)
  [Kernel.singleton_class, Kernel].each do |kernel_class|
    next unless kernel_class.respond_to?(:no_warning_require, true)

    kernel_class.alias_method :require, :no_warning_require
  end
end
