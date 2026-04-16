# typed: strict
# frozen_string_literal: true

require_relative "startup"

HOMEBREW_HELP_MESSAGE = T.let(ENV.fetch("HOMEBREW_HELP_MESSAGE").freeze, String)

HOMEBREW_API_DEFAULT_DOMAIN = T.let(ENV.fetch("HOMEBREW_API_DEFAULT_DOMAIN").freeze, String)
HOMEBREW_BOTTLE_DEFAULT_DOMAIN = T.let(ENV.fetch("HOMEBREW_BOTTLE_DEFAULT_DOMAIN").freeze, String)
HOMEBREW_BREW_DEFAULT_GIT_REMOTE = T.let(ENV.fetch("HOMEBREW_BREW_DEFAULT_GIT_REMOTE").freeze, String)
HOMEBREW_CORE_DEFAULT_GIT_REMOTE = T.let(ENV.fetch("HOMEBREW_CORE_DEFAULT_GIT_REMOTE").freeze, String)

HOMEBREW_DEFAULT_CACHE = T.let(ENV.fetch("HOMEBREW_DEFAULT_CACHE").freeze, String)
HOMEBREW_DEFAULT_LOGS = T.let(ENV.fetch("HOMEBREW_DEFAULT_LOGS").freeze, String)
HOMEBREW_DEFAULT_TEMP = T.let(ENV.fetch("HOMEBREW_DEFAULT_TEMP").freeze, String)
HOMEBREW_REQUIRED_RUBY_VERSION = T.let(ENV.fetch("HOMEBREW_REQUIRED_RUBY_VERSION").freeze, String)

HOMEBREW_PRODUCT = T.let(ENV.fetch("HOMEBREW_PRODUCT").freeze, String)
HOMEBREW_VERSION = T.let(ENV.fetch("HOMEBREW_VERSION").freeze, String)

HOMEBREW_WWW = "https://brew.sh"
HOMEBREW_API_WWW = "https://formulae.brew.sh"
HOMEBREW_DOCS_WWW = "https://docs.brew.sh"

HOMEBREW_SYSTEM = T.let(ENV.fetch("HOMEBREW_SYSTEM").freeze, String)
HOMEBREW_PROCESSOR = T.let(ENV.fetch("HOMEBREW_PROCESSOR").freeze, String)
HOMEBREW_PHYSICAL_PROCESSOR = T.let(ENV.fetch("HOMEBREW_PHYSICAL_PROCESSOR").freeze, String)

HOMEBREW_BREWED_CURL_PATH = T.let(Pathname(ENV.fetch("HOMEBREW_BREWED_CURL_PATH")).freeze, Pathname)
HOMEBREW_USER_AGENT_CURL = T.let(ENV.fetch("HOMEBREW_USER_AGENT_CURL").freeze, String)
HOMEBREW_USER_AGENT_FAKE_SAFARI =
  # Don't update this beyond 10.15.7 until Safari actually updates their
  # user agent to be beyond 10.15.7 (not the case as-of macOS 26)
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " \
  "(KHTML, like Gecko) Version/26.0 Safari/605.1.15"
HOMEBREW_GITHUB_PACKAGES_AUTH = T.let(ENV.fetch("HOMEBREW_GITHUB_PACKAGES_AUTH", "").freeze, String)
HOMEBREW_DEFAULT_PREFIX = T.let(ENV.fetch("HOMEBREW_GENERIC_DEFAULT_PREFIX").freeze, String)
HOMEBREW_DEFAULT_REPOSITORY = T.let(ENV.fetch("HOMEBREW_GENERIC_DEFAULT_REPOSITORY").freeze, String)

HOMEBREW_MACOS_ARM_DEFAULT_PREFIX = T.let(ENV.delete("HOMEBREW_MACOS_ARM_DEFAULT_PREFIX").freeze, T.nilable(String))
HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY = T.let(ENV.delete("HOMEBREW_MACOS_ARM_DEFAULT_REPOSITORY").freeze,
                                              T.nilable(String))
HOMEBREW_LINUX_DEFAULT_PREFIX = T.let(ENV.delete("HOMEBREW_LINUX_DEFAULT_PREFIX").freeze, T.nilable(String))
HOMEBREW_LINUX_DEFAULT_REPOSITORY = T.let(ENV.delete("HOMEBREW_LINUX_DEFAULT_REPOSITORY").freeze, T.nilable(String))

HOMEBREW_PREFIX_PLACEHOLDER = "$HOMEBREW_PREFIX"
HOMEBREW_CELLAR_PLACEHOLDER = "$HOMEBREW_CELLAR"
# Needs a leading slash to avoid `File.expand.path` complaining about non-absolute home.
HOMEBREW_HOME_PLACEHOLDER = "/$HOME"
HOMEBREW_CASK_APPDIR_PLACEHOLDER = "$APPDIR"

HOMEBREW_MACOS_NEWEST_UNSUPPORTED = T.let(ENV.fetch("HOMEBREW_MACOS_NEWEST_UNSUPPORTED").freeze, String)
HOMEBREW_MACOS_NEWEST_SUPPORTED = T.let(ENV.fetch("HOMEBREW_MACOS_NEWEST_SUPPORTED").freeze, String)
HOMEBREW_MACOS_OLDEST_SUPPORTED = T.let(ENV.fetch("HOMEBREW_MACOS_OLDEST_SUPPORTED").freeze, String)
HOMEBREW_MACOS_OLDEST_ALLOWED = T.let(ENV.fetch("HOMEBREW_MACOS_OLDEST_ALLOWED").freeze, String)

HOMEBREW_PULL_OR_COMMIT_URL_REGEX =
  %r[https://github\.com/([\w-]+)/([\w-]+)?/(?:pull/(\d+)|commit/[0-9a-fA-F]{4,40})]
HOMEBREW_BOTTLES_EXTNAME_REGEX = /\.([a-z0-9_]+)\.bottle\.(?:(\d+)\.)?tar\.gz$/

module Homebrew
  DEFAULT_PREFIX = T.let(ENV.fetch("HOMEBREW_DEFAULT_PREFIX").freeze, String)
  DEFAULT_REPOSITORY = T.let(ENV.fetch("HOMEBREW_DEFAULT_REPOSITORY").freeze, String)
  DEFAULT_CELLAR = T.let("#{DEFAULT_PREFIX}/Cellar".freeze, String)
  DEFAULT_MACOS_CELLAR = T.let("#{HOMEBREW_DEFAULT_PREFIX}/Cellar".freeze, String)
  DEFAULT_MACOS_ARM_CELLAR = T.let("#{HOMEBREW_MACOS_ARM_DEFAULT_PREFIX}/Cellar".freeze, String)
  DEFAULT_LINUX_CELLAR = T.let("#{HOMEBREW_LINUX_DEFAULT_PREFIX}/Cellar".freeze, String)

  class << self
    sig { params(failed: T::Boolean).returns(T::Boolean) }
    attr_writer :failed

    sig { params(raise_deprecation_exceptions: T::Boolean).returns(T::Boolean) }
    attr_writer :raise_deprecation_exceptions

    sig { params(auditing: T::Boolean).returns(T::Boolean) }
    attr_writer :auditing

    # Check whether Homebrew is using the default prefix.
    #
    # @api internal
    sig { params(prefix: T.any(Pathname, String)).returns(T::Boolean) }
    def default_prefix?(prefix = HOMEBREW_PREFIX)
      prefix.to_s == DEFAULT_PREFIX
    end

    sig { returns(T::Boolean) }
    def failed?
      @failed ||= T.let(false, T.nilable(T::Boolean))
      @failed == true
    end

    sig { returns(Messages) }
    def messages
      @messages ||= T.let(Messages.new, T.nilable(Messages))
    end

    sig { returns(T::Boolean) }
    def raise_deprecation_exceptions?
      @raise_deprecation_exceptions = T.let(@raise_deprecation_exceptions, T.nilable(T::Boolean))
      @raise_deprecation_exceptions == true
    end

    sig { returns(T::Boolean) }
    def auditing?
      @auditing = T.let(@auditing, T.nilable(T::Boolean))
      @auditing == true
    end

    sig { returns(T::Boolean) }
    def running_as_root?
      @process_euid ||= T.let(Process.euid, T.nilable(Integer))
      @process_euid.zero?
    end

    sig { returns(Integer) }
    def owner_uid
      @owner_uid ||= T.let(HOMEBREW_ORIGINAL_BREW_FILE.stat.uid, T.nilable(Integer))
    end

    sig { returns(T::Boolean) }
    def running_as_root_but_not_owned_by_root?
      running_as_root? && !owner_uid.zero?
    end

    sig { returns(T::Boolean) }
    def auto_update_command?
      ENV.fetch("HOMEBREW_AUTO_UPDATE_COMMAND", false).present?
    end

    sig { params(cmd: T.nilable(String)).void }
    def running_command=(cmd)
      @running_command_with_args = T.let("#{cmd} #{ARGV.join(" ")}", T.nilable(String))
    end

    sig { returns String }
    def running_command_with_args
      "brew #{@running_command_with_args}".strip
    end
  end
end

require "PATH"
ENV["HOMEBREW_PATH"] ||= ENV.fetch("PATH")
ORIGINAL_PATHS = T.let(PATH.new(ENV.fetch("HOMEBREW_PATH")).filter_map do |p|
  Pathname.new(p).expand_path
rescue
  nil
end.freeze, T::Array[Pathname])

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
