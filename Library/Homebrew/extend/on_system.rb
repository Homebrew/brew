# typed: true
# frozen_string_literal: true

require "simulate_system"

module OnSystem
  ARCH_OPTIONS = [:intel, :arm].freeze
  BASE_OS_OPTIONS = [:macos, :linux].freeze
  ALL_OS_OPTIONS = [*MacOSVersion::SYMBOLS.keys, :linux].freeze
  ALL_OS_ARCH_COMBINATIONS = ALL_OS_OPTIONS.product(ARCH_OPTIONS).freeze

  sig { params(arch: Symbol).returns(T::Boolean) }
  def self.arch_condition_met?(arch)
    raise ArgumentError, "Invalid arch condition: #{arch.inspect}" if ARCH_OPTIONS.exclude?(arch)

    arch == Homebrew::SimulateSystem.current_arch
  end

  sig { params(os_name: Symbol, or_condition: T.nilable(Symbol)).returns(T::Boolean) }
  def self.os_condition_met?(os_name, or_condition = nil)
    return Homebrew::SimulateSystem.send(:"simulating_or_running_on_#{os_name}?") if BASE_OS_OPTIONS.include?(os_name)

    raise ArgumentError, "Invalid OS condition: #{os_name.inspect}" unless MacOSVersion::SYMBOLS.key?(os_name)

    if or_condition.present? && [:or_newer, :or_older].exclude?(or_condition)
      raise ArgumentError, "Invalid OS `or_*` condition: #{or_condition.inspect}"
    end

    return false if Homebrew::SimulateSystem.simulating_or_running_on_linux?

    base_os = MacOSVersion.from_symbol(os_name)
    current_os = if Homebrew::SimulateSystem.current_os == :macos
      # Assume the oldest macOS version when simulating a generic macOS version
      # Version::NULL is always treated as less than any other version.
      Version::NULL
    else
      MacOSVersion.from_symbol(Homebrew::SimulateSystem.current_os)
    end

    return current_os >= base_os if or_condition == :or_newer
    return current_os <= base_os if or_condition == :or_older

    current_os == base_os
  end

  sig { params(method_name: Symbol).returns(Symbol) }
  def self.condition_from_method_name(method_name)
    method_name.to_s.sub(/^on_/, "").to_sym
  end

  sig { params(base: Class).void }
  def self.setup_arch_methods(base)
    ARCH_OPTIONS.each do |arch|
      base.define_method(:"on_#{arch}") do |&block|
        @on_system_blocks_exist = true

        return unless OnSystem.arch_condition_met? OnSystem.condition_from_method_name(T.must(__method__))

        @called_in_on_system_block = true
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end

    base.define_method(:on_arch_conditional) do |arm: nil, intel: nil|
      @on_system_blocks_exist = true

      if OnSystem.arch_condition_met? :arm
        arm
      elsif OnSystem.arch_condition_met? :intel
        intel
      end
    end
  end

  sig { params(base: Class).void }
  def self.setup_base_os_methods(base)
    BASE_OS_OPTIONS.each do |base_os|
      base.define_method(:"on_#{base_os}") do |&block|
        @on_system_blocks_exist = true

        return unless OnSystem.os_condition_met? OnSystem.condition_from_method_name(T.must(__method__))

        @called_in_on_system_block = true
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end

    base.define_method(:on_system) do |linux, macos:, &block|
      @on_system_blocks_exist = true

      raise ArgumentError, "The first argument to `on_system` must be `:linux`" if linux != :linux

      os_version, or_condition = if macos.to_s.include?("_or_")
        macos.to_s.split(/_(?=or_)/).map(&:to_sym)
      else
        [macos.to_sym, nil]
      end
      return if !OnSystem.os_condition_met?(os_version, or_condition) && !OnSystem.os_condition_met?(:linux)

      @called_in_on_system_block = true
      result = block.call
      @called_in_on_system_block = false

      result
    end

    base.define_method(:on_system_conditional) do |macos: nil, linux: nil|
      @on_system_blocks_exist = true

      if OnSystem.os_condition_met?(:macos) && macos.present?
        macos
      elsif OnSystem.os_condition_met?(:linux) && linux.present?
        linux
      end
    end
  end

  sig { params(base: Class).void }
  def self.setup_macos_methods(base)
    MacOSVersion::SYMBOLS.each_key do |os_name|
      base.define_method(:"on_#{os_name}") do |or_condition = nil, &block|
        @on_system_blocks_exist = true

        os_condition = OnSystem.condition_from_method_name T.must(__method__)
        return unless OnSystem.os_condition_met? os_condition, or_condition

        @called_in_on_system_block = true
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end
  end

  sig { params(_base: Class).void }
  def self.included(_base)
    raise "Do not include `OnSystem` directly. Instead, include `OnSystem::MacOSAndLinux` or `OnSystem::MacOSOnly`"
  end

  module MacOSAndLinux
    sig { params(base: Class).void }
    def self.included(base)
      OnSystem.setup_arch_methods(base)
      OnSystem.setup_base_os_methods(base)
      OnSystem.setup_macos_methods(base)
    end
  end

  module MacOSOnly
    sig { params(base: Class).void }
    def self.included(base)
      OnSystem.setup_arch_methods(base)
      OnSystem.setup_macos_methods(base)
    end
  end
end
