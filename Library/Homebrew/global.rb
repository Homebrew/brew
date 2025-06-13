# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require_relative "startup"

HOMEBREW_HELP_MESSAGE = ENV.fetch("HOMEBREW_HELP_MESSAGE").freeze

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

HOMEBREW_MACOS_ARM_DEFAULT_PREFIX = ENV.delete("HOMEBREW_MACOS_ARM_DEFAULT_PREFIX").freeze
HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY = ENV.delete("HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY").freeze
HOMEBREW_LINUX_DEFAULT_PREFIX = ENV.delete("HOMEBREW_LINUX_DEFAULT_PREFIX").freeze
HOMEBREW_LINUX_DEFAULT_REPOSITORY = ENV.delete("HOMEBREW_LINUX_DEFAULT_REPOSITORY").freeze

HOMEBREW_PREFIX_PLACEHOLDER = "$HOMEBREW_PREFIX"
HOMEBREW_CELLAR_PLACEHOLDER = "$HOMEBREW_CELLAR"
# Needs a leading slash to avoid `File.expand.path` complaining about non-absolute home.
HOMEBREW_HOME_PLACEHOLDER = "/$HOME"
HOMEBREW_CASK_APPDIR_PLACEHOLDER = "$APPDIR"

HOMEBREW_MACOS_NEWEST_UNSUPPORTED = ENV.fetch("HOMEBREW_MACOS_NEWEST_UNSUPPORTED").freeze
HOMEBREW_MACOS_NEWEST_SUPPORTED = ENV.fetch("HOMEBREW_MACOS_NEWEST_SUPPORTED").freeze
HOMEBREW_MACOS_OLDEST_SUPPORTED = ENV.fetch("HOMEBREW_MACOS_OLDEST_SUPPORTED").freeze
HOMEBREW_MACOS_OLDEST_ALLOWED = ENV.fetch("HOMEBREW_MACOS_OLDEST_ALLOWED").freeze

HOMEBREW_PULL_API_REGEX =
  %r{https://api\.github\.com/repos/([\w-]+)/([\w-]+)?/pulls/(\d+)}
HOMEBREW_PULL_OR_COMMIT_URL_REGEX =
  %r[https://github\.com/([\w-]+)/([\w-]+)?/(?:pull/(\d+)|commit/[0-9a-fA-F]{4,40})]
HOMEBREW_BOTTLES_EXTNAME_REGEX = /\.([a-z0-9_]+)\.bottle\.(?:(\d+)\.)?tar\.gz$/

module Homebrew
  DEFAULT_PREFIX = T.let(ENV.fetch("HOMEBREW_DEFAULT_PREFIX").freeze, String)
  DEFAULT_REPOSITORY = T.let(ENV.fetch("HOMEBREW_DEFAULT_REPOSITORY").freeze, String)
  DEFAULT_CELLAR = "#{DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_MACOS_CELLAR = "#{HOMEBREW_DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_MACOS_ARM_CELLAR = "#{HOMEBREW_MACOS_ARM_DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_LINUX_CELLAR = "#{HOMEBREW_LINUX_DEFAULT_PREFIX}/Cellar".freeze

  class << self
    attr_writer :failed, :raise_deprecation_exceptions, :auditing

    # Check whether Homebrew is using the default prefix.
    #
    # @api internal
    sig { params(prefix: T.any(Pathname, String)).returns(T::Boolean) }
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
      @process_euid ||= Process.euid
      @process_euid.zero?
    end

    def owner_uid
      @owner_uid ||= HOMEBREW_ORIGINAL_BREW_FILE.stat.uid
    end

    def running_as_root_but_not_owned_by_root?
      running_as_root? && !owner_uid.zero?
    end

    def auto_update_command?
      ENV.fetch("HOMEBREW_AUTO_UPDATE_COMMAND", false).present?
    end

    sig { params(cmd: T.nilable(String)).void }
    def running_command=(cmd)
      @running_command_with_args = "#{cmd} #{ARGV.join(" ")}"
    end

    sig { returns String }
    def running_command_with_args
      "brew #{@running_command_with_args}".strip
    end
  end
end

require "PATH"
ENV["HOMEBREW_PATH"] ||= ENV.fetch("PATH")
ORIGINAL_PATHS = PATH.new(ENV.fetch("HOMEBREW_PATH")).filter_map do |p|
  Pathname.new(p).expand_path
rescue
  nil
end.freeze

require "extend/blank"
require "extend/kernel"
require "os"

require "extend/array"
require "cachable"
require "extend/enumerable"
require "extend/string"
require "extend/pathname"

require "exceptions"

require "tap_constants"
require "official_taps"
