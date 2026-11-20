# typed: strict
# frozen_string_literal: true

require "simulate_system"

module OnSystem
  ARCH_OPTIONS = [:intel, :arm].freeze
  BASE_OS_OPTIONS = [:macos, :linux].freeze
  ALL_OS_OPTIONS = T.let([*MacOSVersion::SYMBOLS.keys, :linux].freeze, T::Array[Symbol])
  ALL_OS_ARCH_COMBINATIONS = T.let(ALL_OS_OPTIONS.product(ARCH_OPTIONS).freeze, T::Array[[Symbol, Symbol]])

  valid_os_arch_tags = ALL_OS_ARCH_COMBINATIONS.map do |os, arch|
    Utils::Bottles::Tag.new(system: os, arch:)
  end
  VALID_OS_ARCH_TAGS = T.let(valid_os_arch_tags.freeze, T::Array[Utils::Bottles::Tag])

  sig { params(arch: Symbol).returns(T::Boolean) }
  def self.arch_condition_met?(arch)
    raise ArgumentError, "Invalid arch condition: #{arch.inspect}" if ARCH_OPTIONS.exclude?(arch)

    arch == Homebrew::SimulateSystem.current_arch
  end

  sig { params(os_name: Symbol, or_condition: T.nilable(Symbol)).returns(T::Boolean) }
  def self.os_condition_met?(os_name, or_condition = nil)
    if BASE_OS_OPTIONS.include?(os_name)
      return Homebrew::SimulateSystem.public_send(:"simulating_or_running_on_#{os_name}?")
    end

    raise ArgumentError, "Invalid OS condition: #{os_name.inspect}" unless MacOSVersion::SYMBOLS.key?(os_name)

    if or_condition.present? && [:or_newer, :or_older].exclude?(or_condition)
      raise ArgumentError, "Invalid OS `or_*` condition: #{or_condition.inspect}"
    end

    return false unless Homebrew::SimulateSystem.simulating_or_running_on_macos?

    base_os = MacOSVersion.from_symbol(os_name)
    current_os = if Homebrew::SimulateSystem.current_os == :macos
      # Assume the oldest macOS version when simulating a generic macOS version.
      # Version::NULL is always treated as less than any other version.
      Version::NULL
    else
      MacOSVersion.from_symbol(Homebrew::SimulateSystem.current_os)
    end

    return current_os >= base_os if or_condition == :or_newer
    return current_os <= base_os if or_condition == :or_older

    current_os == base_os
  end

  autoload :DSL, "on_system/dsl"
  autoload :MacOSAndLinux, "on_system/dsl"
  autoload :MacOSOnly, "on_system/dsl"

  sig { params(_base: T::Class[T.anything]).void }
  def self.included(_base)
    raise "Do not include `OnSystem` directly. Instead, include `OnSystem::MacOSAndLinux` or `OnSystem::MacOSOnly`"
  end
end
