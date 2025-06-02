# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require_relative "startup"

DINRUSBREW_HELP_MESSAGE = ENV.fetch("DINRUSBREW_HELP_MESSAGE").freeze

DINRUSBREW_API_DEFAULT_DOMAIN = ENV.fetch("DINRUSBREW_API_DEFAULT_DOMAIN").freeze
DINRUSBREW_BOTTLE_DEFAULT_DOMAIN = ENV.fetch("DINRUSBREW_BOTTLE_DEFAULT_DOMAIN").freeze
DINRUSBREW_BREW_DEFAULT_GIT_REMOTE = ENV.fetch("DINRUSBREW_BREW_DEFAULT_GIT_REMOTE").freeze
DINRUSBREW_CORE_DEFAULT_GIT_REMOTE = ENV.fetch("DINRUSBREW_CORE_DEFAULT_GIT_REMOTE").freeze
DINRUSBREW_DEFAULT_CACHE = ENV.fetch("DINRUSBREW_DEFAULT_CACHE").freeze
DINRUSBREW_DEFAULT_LOGS = ENV.fetch("DINRUSBREW_DEFAULT_LOGS").freeze
DINRUSBREW_DEFAULT_TEMP = ENV.fetch("DINRUSBREW_DEFAULT_TEMP").freeze
DINRUSBREW_REQUIRED_RUBY_VERSION = ENV.fetch("DINRUSBREW_REQUIRED_RUBY_VERSION").freeze

DINRUSBREW_PRODUCT = ENV.fetch("DINRUSBREW_PRODUCT").freeze
DINRUSBREW_VERSION = ENV.fetch("DINRUSBREW_VERSION").freeze
DINRUSBREW_WWW = "https://brew.sh"
DINRUSBREW_API_WWW = "https://formulae.brew.sh"
DINRUSBREW_DOCS_WWW = "https://docs.brew.sh"
DINRUSBREW_SYSTEM = ENV.fetch("DINRUSBREW_SYSTEM").freeze
DINRUSBREW_PROCESSOR = ENV.fetch("DINRUSBREW_PROCESSOR").freeze
DINRUSBREW_PHYSICAL_PROCESSOR = ENV.fetch("DINRUSBREW_PHYSICAL_PROCESSOR").freeze

DINRUSBREW_BREWED_CURL_PATH = Pathname(ENV.fetch("DINRUSBREW_BREWED_CURL_PATH")).freeze
DINRUSBREW_USER_AGENT_CURL = ENV.fetch("DINRUSBREW_USER_AGENT_CURL").freeze
DINRUSBREW_USER_AGENT_RUBY =
  "#{ENV.fetch("DINRUSBREW_USER_AGENT")} ruby/#{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}".freeze
DINRUSBREW_USER_AGENT_FAKE_SAFARI =
  # Don't update this beyond 10.15.7 until Safari actually updates their
  # user agent to be beyond 10.15.7 (not the case as-of macOS 14)
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " \
  "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"
DINRUSBREW_GITHUB_PACKAGES_AUTH = ENV.fetch("DINRUSBREW_GITHUB_PACKAGES_AUTH").freeze

DINRUSBREW_DEFAULT_PREFIX = ENV.fetch("DINRUSBREW_GENERIC_DEFAULT_PREFIX").freeze
DINRUSBREW_DEFAULT_REPOSITORY = ENV.fetch("DINRUSBREW_GENERIC_DEFAULT_REPOSITORY").freeze
DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX = ENV.fetch("DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX").freeze
DINRUSBREW_MACOS_ARM_DEFAULT_REPOSITORY = ENV.fetch("DINRUSBREW_MACOS_ARM_DEFAULT_REPOSITORY").freeze
DINRUSBREW_LINUX_DEFAULT_PREFIX = ENV.fetch("DINRUSBREW_LINUX_DEFAULT_PREFIX").freeze
DINRUSBREW_LINUX_DEFAULT_REPOSITORY = ENV.fetch("DINRUSBREW_LINUX_DEFAULT_REPOSITORY").freeze
DINRUSBREW_PREFIX_PLACEHOLDER = "$DINRUSBREW_PREFIX"
DINRUSBREW_CELLAR_PLACEHOLDER = "$DINRUSBREW_CELLAR"
# Needs a leading slash to avoid `File.expand.path` complaining about non-absolute home.
DINRUSBREW_HOME_PLACEHOLDER = "/$HOME"
DINRUSBREW_CASK_APPDIR_PLACEHOLDER = "$APPDIR"

DINRUSBREW_MACOS_NEWEST_UNSUPPORTED = ENV.fetch("DINRUSBREW_MACOS_NEWEST_UNSUPPORTED").freeze
DINRUSBREW_MACOS_OLDEST_SUPPORTED = ENV.fetch("DINRUSBREW_MACOS_OLDEST_SUPPORTED").freeze
DINRUSBREW_MACOS_OLDEST_ALLOWED = ENV.fetch("DINRUSBREW_MACOS_OLDEST_ALLOWED").freeze

DINRUSBREW_PULL_API_REGEX =
  %r{https://api\.github\.com/repos/([\w-]+)/([\w-]+)?/pulls/(\d+)}
DINRUSBREW_PULL_OR_COMMIT_URL_REGEX =
  %r[https://github\.com/([\w-]+)/([\w-]+)?/(?:pull/(\d+)|commit/[0-9a-fA-F]{4,40})]
DINRUSBREW_BOTTLES_EXTNAME_REGEX = /\.([a-z0-9_]+)\.bottle\.(?:(\d+)\.)?tar\.gz$/

module DinrusBrew
  extend FileUtils

  DEFAULT_PREFIX = T.let(ENV.fetch("DINRUSBREW_DEFAULT_PREFIX").freeze, String)
  DEFAULT_REPOSITORY = T.let(ENV.fetch("DINRUSBREW_DEFAULT_REPOSITORY").freeze, String)
  DEFAULT_CELLAR = "#{DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_MACOS_CELLAR = "#{DINRUSBREW_DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_MACOS_ARM_CELLAR = "#{DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX}/Cellar".freeze
  DEFAULT_LINUX_CELLAR = "#{DINRUSBREW_LINUX_DEFAULT_PREFIX}/Cellar".freeze

  class << self
    attr_writer :failed, :raise_deprecation_exceptions, :auditing

    # Check whether DinrusBrew is using the default prefix.
    #
    # @api internal
    sig { params(prefix: T.any(Pathname, String)).returns(T::Boolean) }
    def default_prefix?(prefix = DINRUSBREW_PREFIX)
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
      @owner_uid ||= DINRUSBREW_ORIGINAL_BREW_FILE.stat.uid
    end

    def running_as_root_but_not_owned_by_root?
      running_as_root? && !owner_uid.zero?
    end

    def auto_update_command?
      ENV.fetch("DINRUSBREW_AUTO_UPDATE_COMMAND", false).present?
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
ENV["DINRUSBREW_PATH"] ||= ENV.fetch("PATH")
ORIGINAL_PATHS = PATH.new(ENV.fetch("DINRUSBREW_PATH")).filter_map do |p|
  Pathname.new(p).expand_path
rescue
  nil
end.freeze

require "extend/blank"
require "extend/kernel"
require "os"

require "extend/array"
require "extend/cachable"
require "extend/enumerable"
require "extend/string"
require "extend/pathname"

require "exceptions"

require "tap_constants"
require "official_taps"
