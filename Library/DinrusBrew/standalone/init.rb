# typed: true
# frozen_string_literal: true

# This file is included before any other files. It intentionally has typing disabled and has minimal use of `require`.

required_ruby_major, required_ruby_minor, = ENV.fetch("DINRUSBREW_REQUIRED_RUBY_VERSION", "").split(".").map(&:to_i)
gems_vendored = if required_ruby_minor.nil?
  # We're likely here if running RuboCop etc, so just assume we don't need to install gems as we likely already have
  true
else
  ruby_major, ruby_minor, = RUBY_VERSION.split(".").map(&:to_i)
  raise "Could not parse Ruby requirements" if !ruby_major || !ruby_minor || !required_ruby_major

  if ruby_major < required_ruby_major || (ruby_major == required_ruby_major && ruby_minor < required_ruby_minor)
    raise "DinrusBrew must be run under Ruby #{required_ruby_major}.#{required_ruby_minor}! " \
          "You're running #{RUBY_VERSION}."
  end

  # This list should match .gitignore
  vendored_versions = ["3.3"].freeze
  vendored_versions.include?("#{ruby_major}.#{ruby_minor}")
end.freeze

# We trust base Ruby to provide what we need.
# Don't look into the user-installed sitedir, which may contain older versions of RubyGems.
require "rbconfig"
$LOAD_PATH.reject! { |path| path.start_with?(RbConfig::CONFIG["sitedir"]) }

require "pathname"
dir = __dir__ || raise("__dir__ is not defined")
DINRUSBREW_LIBRARY_PATH = Pathname(dir).parent.realpath.freeze
DINRUSBREW_USING_PORTABLE_RUBY = RbConfig.ruby.include?("/vendor/portable-ruby/").freeze

require_relative "../utils/gems"
DinrusBrew.setup_gem_environment!(setup_path: false)

# Install gems for Rubies we don't vendor for.
if !gems_vendored && !ENV["DINRUSBREW_SKIP_INITIAL_GEM_INSTALL"]
  DinrusBrew.install_bundler_gems!(setup_path: false)
  ENV["DINRUSBREW_SKIP_INITIAL_GEM_INSTALL"] = "1"
end

unless $LOAD_PATH.include?(DINRUSBREW_LIBRARY_PATH.to_s)
  # Insert the path after any existing DinrusBrew paths (e.g. those inserted by tests and parent processes)
  last_homebrew_path_idx = $LOAD_PATH.rindex do |path|
    path.start_with?(DINRUSBREW_LIBRARY_PATH.to_s) && !path.include?("vendor/portable-ruby")
  end || -1
  $LOAD_PATH.insert(last_homebrew_path_idx + 1, DINRUSBREW_LIBRARY_PATH.to_s)
end
require_relative "../vendor/bundle/bundler/setup"
require "portable_ruby_gems" if DINRUSBREW_USING_PORTABLE_RUBY
$LOAD_PATH.unshift "#{DINRUSBREW_LIBRARY_PATH}/vendor/bundle/#{RUBY_ENGINE}/#{Gem.ruby_api_version}/gems/" \
                   "bundler-#{DinrusBrew::DINRUSBREW_BUNDLER_VERSION}/lib"
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
