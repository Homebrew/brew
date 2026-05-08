# typed: strict
# frozen_string_literal: true

require "version"

# Helper functions for querying operating system information.
module OS
  # Check whether the operating system is macOS.
  #
  # @api public
  sig { returns(T::Boolean) }
  def self.mac?
    return false if ENV["HOMEBREW_TEST_GENERIC_OS"]

    RbConfig::CONFIG["host_os"].include? "darwin"
  end

  # Check whether the operating system is Linux.
  #
  # @api public
  sig { returns(T::Boolean) }
  def self.linux?
    return false if ENV["HOMEBREW_TEST_GENERIC_OS"]

    RbConfig::CONFIG["host_os"].include? "linux"
  end

  # Get the kernel version.
  #
  # @api public
  sig { returns(Version) }
  def self.kernel_version
    require "etc"
    @kernel_version ||= T.let(Version.new(Etc.uname.fetch(:release)), T.nilable(Version))
  end

  # Get the kernel name.
  #
  # @api public
  sig { returns(String) }
  def self.kernel_name
    require "etc"
    @kernel_name ||= T.let(Etc.uname.fetch(:sysname), T.nilable(String))
  end

  ::OS_VERSION = T.let(ENV.fetch("HOMEBREW_OS_VERSION").freeze, String)

  # See Linux-CI.md
  LINUX_CI_OS_VERSION = "Ubuntu 22.04"
  LINUX_CI_ARM_RUNNER = "ubuntu-22.04-arm"
  LINUX_GLIBC_CI_VERSION = "2.35"
  LINUX_GLIBC_NEXT_CI_VERSION = "2.39" # users below this version will be warned by `brew doctor`
  LINUX_GCC_CI_VERSION = "12" # https://packages.ubuntu.com/jammy/gcc-12
  LINUX_LIBSTDCXX_CI_VERSION = "6.0.30" # https://packages.ubuntu.com/jammy/libstdc++6
  LINUX_PREFERRED_GCC_COMPILER_FORMULA = T.let("gcc@#{LINUX_GCC_CI_VERSION}".freeze, String)
  LINUX_PREFERRED_GCC_RUNTIME_FORMULA = "gcc"

  sig { returns(T::Boolean) }
  def self.nix_managed_homebrew?
    nix_homebrew? || nix_darwin?
  end

  sig { returns(String) }
  def self.nix_managed_homebrew_issues_url
    if nix_homebrew?
      "https://github.com/zhaofengli/nix-homebrew/issues"
    else
      "https://github.com/nix-darwin/nix-darwin/issues"
    end
  end

  sig { returns(T::Boolean) }
  def self.nix_homebrew?
    # nix-homebrew sets this repository name, creates this prefix marker and
    # exports these update values.
    # https://github.com/zhaofengli/nix-homebrew/blob/aeb2069920742d0d6570089e8b3b8620050bacf2/modules/default.nix#L29-L31
    # https://github.com/zhaofengli/nix-homebrew/blob/aeb2069920742d0d6570089e8b3b8620050bacf2/modules/default.nix#L115-L125
    HOMEBREW_REPOSITORY.basename.to_s == ".homebrew-is-managed-by-nix" ||
      (HOMEBREW_PREFIX/".managed_by_nix_darwin").exist? ||
      (ENV["HOMEBREW_UPDATE_BEFORE"] == "nix" && ENV["HOMEBREW_UPDATE_AFTER"] == "nix")
  end
  private_class_method :nix_homebrew?

  sig { returns(T::Boolean) }
  def self.nix_darwin?
    # nix-darwin manages Homebrew through `brew bundle` during activation.
    # https://github.com/nix-darwin/nix-darwin/blob/8c62fba0854ba15c8917aed18894dbccb48a3777/modules/homebrew.nix#L76-L129
    ENV.fetch("HOMEBREW_BUNDLE_FILE", "").start_with?("/nix/store/") ||
      ARGV.each_cons(2).any? { |arg, value| arg == "--file" && value.start_with?("/nix/store/") } ||
      ARGV.any? { |arg| arg.start_with?("--file=/nix/store/") }
  end
  private_class_method :nix_darwin?

  nix_managed_homebrew = T.let(OS.nix_managed_homebrew?, T::Boolean)

  if OS.mac?
    require "os/mac"
    require "hardware"
    # Don't tell people to report issues on non-Tier 1 configurations.
    if nix_managed_homebrew
      ISSUES_URL = OS.nix_managed_homebrew_issues_url.freeze
    elsif !OS::Mac.version.prerelease? &&
          !OS::Mac.version.outdated_release? &&
          ARGV.none? { |v| v.start_with?("--cc=") } &&
          (HOMEBREW_PREFIX.to_s == HOMEBREW_DEFAULT_PREFIX ||
          (HOMEBREW_PREFIX.to_s == HOMEBREW_MACOS_ARM_DEFAULT_PREFIX && Hardware::CPU.arm?))
      ISSUES_URL = "https://docs.brew.sh/Troubleshooting"
    end
    PATH_OPEN = "/usr/bin/open"
  elsif OS.linux?
    require "os/linux"
    ISSUES_URL = if nix_managed_homebrew
      OS.nix_managed_homebrew_issues_url
    else
      "https://docs.brew.sh/Troubleshooting"
    end.freeze
    PATH_OPEN = if OS::Linux.wsl? && (wslview = which("wslview").presence)
      wslview.to_s
    else
      "xdg-open"
    end.freeze
  end

  sig { returns(T::Boolean) }
  def self.not_tier_one_configuration?
    !defined?(OS::ISSUES_URL)
  end
end
