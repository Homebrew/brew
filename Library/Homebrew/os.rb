# typed: strict
# frozen_string_literal: true

require "version"
require "os/third_party_homebrew"

# Helper functions for querying operating system information.
module OS
  @kernel_version = T.let(nil, T.nilable(Version))

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

  # Check whether the operating system is Linux on windows (WSL).
  #
  # @api public
  sig { returns(T::Boolean) }
  def self.wsl?
    return false if ENV["HOMEBREW_TEST_GENERIC_OS"]

    /-microsoft/i.match?(kernel_version.to_s)
  end

  # Get the kernel version.
  #
  # @api public
  sig { returns(Version) }
  def self.kernel_version
    require "etc"
    @kernel_version ||= Version.new(Etc.uname.fetch(:release))
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
  LINUX_CI_OS_VERSION = "Ubuntu 24.04"
  LINUX_CI_ARM_RUNNER = "ubuntu-24.04-arm"
  LINUX_GLIBC_CI_VERSION = "2.39"
  LINUX_GLIBC_NEXT_CI_VERSION = "2.39" # users below this version will be warned by `brew doctor`
  LINUX_GCC_CI_VERSION = "13" # https://packages.ubuntu.com/noble/gcc
  LINUX_LIBSTDCXX_CI_VERSION = "6.0.33" # https://packages.ubuntu.com/noble/libstdc++6
  LINUX_PREFERRED_GCC_COMPILER_FORMULA = T.let("gcc@#{LINUX_GCC_CI_VERSION}".freeze, String)
  LINUX_PREFERRED_GCC_RUNTIME_FORMULA = "gcc"

  # The third-party configuration detected at startup, if any.
  sig { returns(T.nilable(ThirdPartyHomebrew)) }
  def self.third_party_homebrew
    @third_party_homebrew
  end

  sig { returns(T::Boolean) }
  def self.third_party_homebrew?
    !third_party_homebrew.nil?
  end

  @third_party_homebrew = T.let(nil, T.nilable(ThirdPartyHomebrew))
  @third_party_homebrew = ThirdPartyHomebrew.detect if mac? || linux?

  if OS.mac?
    require "os/mac"
    require "hardware"
    PATH_OPEN = "/usr/bin/open"
  elsif OS.linux?
    require "os/linux"
    PATH_OPEN = if wsl? && (wslview = which("wslview"))
      wslview.to_s
    else
      "xdg-open"
    end.freeze
  end

  issues_url = if (provider = third_party_homebrew)
    provider.issues_url
  elsif OS.linux? || (OS.mac? && Hardware::CPU.arm? &&
                      !OS::Mac.version.prerelease? && !OS::Mac.version.outdated_release? &&
                      ARGV.none? { |arg| arg.start_with?("--cc=") })
    "https://docs.brew.sh/Troubleshooting"
  end
  ISSUES_URL = T.let(issues_url.freeze, T.nilable(String))

  sig { returns(T::Boolean) }
  def self.not_tier_one_configuration?
    return true if third_party_homebrew? || ISSUES_URL.nil?

    require "diagnostic"
    Homebrew::Diagnostic.support_tier != 1
  end
end
