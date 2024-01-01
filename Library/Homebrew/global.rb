# typed: true
# frozen_string_literal: true

require_relative "startup"

require "English"
require "fileutils"
require "json"
require "json/add/exception"
require "forwardable"
require "set"

# Only require "core_ext" here to ensure we're only requiring the minimum of
# what we need.
require "active_support/core_ext/array/access"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/file/atomic"
require "active_support/core_ext/hash/deep_merge"
require "active_support/core_ext/hash/keys"
require "active_support/core_ext/string/exclude"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/string/indent"

HOMEBREW_API_DEFAULT_DOMAIN = ENV.fetch("HOMEBREW_API_DEFAULT_DOMAIN").freeze
HOMEBREW_BOTTLE_DEFAULT_DOMAIN = ENV.fetch("HOMEBREW_BOTTLE_DEFAULT_DOMAIN").freeze
HOMEBREW_BREW_DEFAULT_GIT_REMOTE = ENV.fetch("HOMEBREW_BREW_DEFAULT_GIT_REMOTE").freeze
HOMEBREW_CORE_DEFAULT_GIT_REMOTE = ENV.fetch("HOMEBREW_CORE_DEFAULT_GIT_REMOTE").freeze
HOMEBREW_DEFAULT_CACHE = ENV.fetch("HOMEBREW_DEFAULT_CACHE").freeze
HOMEBREW_DEFAULT_LOGS = ENV.fetch("HOMEBREW_DEFAULT_LOGS").freeze
HOMEBREW_DEFAULT_TEMP = ENV.fetch("HOMEBREW_DEFAULT_TEMP").freeze
HOMEBREW_REQUIRED_RUBY_VERSION = ENV.fetch("HOMEBREW_REQUIRED_RUBY_VERSION").freeze

HOMEBREW_PRODUCT = ENV.fetch("HOMEBREW_PRODUCT").freeze
HOMEBREW_VERSION = ENV.fetch("HOMEBREW_VERSION").freeze
HOMEBREW_WWW = "https://brew.sh"
HOMEBREW_API_WWW = "https://formulae.brew.sh"
HOMEBREW_DOCS_WWW = "https://docs.brew.sh"
HOMEBREW_SYSTEM = ENV.fetch("HOMEBREW_SYSTEM").freeze
HOMEBREW_PROCESSOR = ENV.fetch("HOMEBREW_PROCESSOR").freeze
HOMEBREW_PHYSICAL_PROCESSOR = ENV.fetch("HOMEBREW_PHYSICAL_PROCESSOR").freeze

HOMEBREW_BREWED_CURL_PATH = Pathname(ENV.fetch("HOMEBREW_BREWED_CURL_PATH")).freeze
HOMEBREW_USER_AGENT_CURL = ENV.fetch("HOMEBREW_USER_AGENT_CURL").freeze
HOMEBREW_USER_AGENT_RUBY =
  "#{ENV.fetch("HOMEBREW_USER_AGENT")} ruby/#{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}".freeze
HOMEBREW_USER_AGENT_FAKE_SAFARI =
  # Don't update this beyond 10.15.7 until Safari actually updates their
  # user agent to be beyond 10.15.7 (not the case as-of macOS 14)
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " \
  "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
HOMEBREW_GITHUB_PACKAGES_AUTH = ENV.fetch("HOMEBREW_GITHUB_PACKAGES_AUTH").freeze

HOMEBREW_DEFAULT_PREFIX = ENV.fetch("HOMEBREW_GENERIC_DEFAULT_PREFIX").freeze
HOMEBREW_DEFAULT_REPOSITORY = ENV.fetch("HOMEBREW_GENERIC_DEFAULT_REPOSITORY").freeze
HOMEBREW_MACOS_ARM_DEFAULT_PREFIX = ENV.fetch("HOMEBREW_MACOS_ARM_DEFAULT_PREFIX").freeze
HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY = ENV.fetch("HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY").freeze
HOMEBREW_LINUX_DEFAULT_PREFIX = ENV.fetch("HOMEBREW_LINUX_DEFAULT_PREFIX").freeze
HOMEBREW_LINUX_DEFAULT_REPOSITORY = ENV.fetch("HOMEBREW_LINUX_DEFAULT_REPOSITORY").freeze
HOMEBREW_PREFIX_PLACEHOLDER = "$HOMEBREW_PREFIX"
HOMEBREW_CELLAR_PLACEHOLDER = "$HOMEBREW_CELLAR"
# Needs a leading slash to avoid `File.expand.path` complaining about non-absolute home.
HOMEBREW_HOME_PLACEHOLDER = "/$HOME"
HOMEBREW_CASK_APPDIR_PLACEHOLDER = "$APPDIR"

HOMEBREW_MACOS_NEWEST_UNSUPPORTED = ENV.fetch("HOMEBREW_MACOS_NEWEST_UNSUPPORTED").freeze
HOMEBREW_MACOS_OLDEST_SUPPORTED = ENV.fetch("HOMEBREW_MACOS_OLDEST_SUPPORTED").freeze
HOMEBREW_MACOS_OLDEST_ALLOWED = ENV.fetch("HOMEBREW_MACOS_OLDEST_ALLOWED").freeze

HOMEBREW_PULL_API_REGEX =
  %r{https://api\.github\.com/repos/([\w-]+)/([\w-]+)?/pulls/(\d+)}.freeze
HOMEBREW_PULL_OR_COMMIT_URL_REGEX =
  %r[https://github\.com/([\w-]+)/([\w-]+)?/(?:pull/(\d+)|commit/[0-9a-fA-F]{4,40})].freeze
HOMEBREW_BOTTLES_EXTNAME_REGEX = /\.([a-z0-9_]+)\.bottle\.(?:(\d+)\.)?tar\.gz$/.freeze

require "extend/module"
require "extend/blank"
require "env_config"
require "macos_version"
require "os"
require "messages"
require "default_prefix"

module Homebrew
  extend FileUtils

  DEFAULT_CELLAR = "#{DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_MACOS_CELLAR = "#{HOMEBREW_DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_MACOS_ARM_CELLAR = "#{HOMEBREW_MACOS_ARM_DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_LINUX_CELLAR = "#{HOMEBREW_LINUX_DEFAULT_PREFIX}/Cellar".freeze

  class << self
    attr_writer :failed, :raise_deprecation_exceptions, :auditing

    def default_prefix?(prefix = HOMEBREW_PREFIX)
      prefix.to_s == DEFAULT_PREFIX
    end

    def failed?
      @failed ||= false
      @failed == true
    end

    def messages
      @messages ||= Messages.new
    end

    def raise_deprecation_exceptions?
      @raise_deprecation_exceptions == true
    end

    def auditing?
      @auditing == true
    end

    def running_as_root?
      @process_uid ||= Process.uid
      @process_uid.zero?
    end

    def owner_uid
      @owner_uid ||= HOMEBREW_BREW_FILE.stat.uid
    end

    def running_as_root_but_not_owned_by_root?
      running_as_root? && !owner_uid.zero?
    end

    def auto_update_command?
      ENV.fetch("HOMEBREW_AUTO_UPDATE_COMMAND", false).present?
    end
  end
end

require "context"
require "extend/array"
require "git_repository"
require "extend/pathname"
require "cli/args"

require "PATH"

ENV["HOMEBREW_PATH"] ||= ENV.fetch("PATH")
ORIGINAL_PATHS = PATH.new(ENV.fetch("HOMEBREW_PATH")).map do |p|
  Pathname.new(p).expand_path
rescue
  nil
end.compact.freeze

require "system_command"
require "exceptions"
require "utils"

require "official_taps"
require "tap"
require "tap_constants"
