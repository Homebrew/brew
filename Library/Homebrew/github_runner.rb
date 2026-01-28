# typed: strict
# frozen_string_literal: true

require "linux_runner_spec"
require "macos_runner_spec"

class GitHubRunner < T::Struct
  const :platform, Symbol
  const :arch, Symbol
  const :spec, T.any(LinuxRunnerSpec, MacOSRunnerSpec)
  const :macos_version, T.nilable(MacOSVersion)
  prop  :active, T::Boolean, default: false

  sig { returns(T::Boolean) }
  def macos?
    platform == :macos
  end

  sig { returns(T::Boolean) }
  def linux?
    platform == :linux
  end

  sig { returns(T::Boolean) }
  def x86_64?
    arch == :x86_64
  end

  sig { returns(T::Boolean) }
  def arm64?
    arch == :arm64
  end
end
