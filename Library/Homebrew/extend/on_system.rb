# typed: strict
# frozen_string_literal: true

require "requirements/macos_requirement"
require "simulate_system"

module OnSystem
  ARCH_OPTIONS = T.let([:intel, :arm].freeze, T::Array[Symbol])
  BASE_OS_OPTIONS = T.let([:macos, :linux].freeze, T::Array[Symbol])
  ALL_OS_OPTIONS = T.let([*MacOSVersion::SYMBOLS.keys, :linux].freeze, T::Array[Symbol])
  ALL_OS_ARCH_COMBINATIONS = T.let(
    ALL_OS_OPTIONS.product(ARCH_OPTIONS).freeze,
    T::Array[[Symbol, Symbol]],
  )

  VALID_OS_ARCH_TAGS = T.let(
    ALL_OS_ARCH_COMBINATIONS.filter_map do |os, arch|
      tag = Utils::Bottles::Tag.new(system: os, arch:)
      next unless tag.valid_combination?

      tag
    end.freeze,
    T::Array[Utils::Bottles::Tag],
  )

  class UsesOnSystem < T::Struct
    prop :arm, T::Boolean, default: false
    prop :intel, T::Boolean, default: false
    prop :linux, T::Boolean, default: false
    prop :macos, T::Boolean, default: false
    prop :macos_requirements, T::Set[MacOSRequirement], default: Set[]

    alias arm? arm
    alias intel? intel
    alias linux? linux
    alias macos? macos

    # Whether the object has only default values.
    sig { returns(T::Boolean) }
    def empty?
      !@arm && !@intel && !@linux && !@macos && @macos_requirements.empty?
    end

    # Whether the object has any non-default values.
    sig { returns(T::Boolean) }
    def present? = !empty?
  end

  # Converts an `or_condition` value to a suitable `MacOSRequirements`
  # `comparator` string, defaulting to `==` if the provided argument is `nil`.
  sig { params(symbol: T.nilable(Symbol)).returns(String) }
  def self.comparator_from_or_condition(symbol)
    case symbol
    when :or_newer
      ">="
    when :or_older
      "<="
    else
      "=="
    end
  end

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

    current_os_symbol = Homebrew::SimulateSystem.current_os
    current_os = if current_os_symbol == :macos
      # Assume the oldest macOS version when simulating a generic macOS version
      # Version::NULL is always treated as less than any other version.
      Version::NULL
    elsif MacOSVersion::SYMBOLS.key?(current_os_symbol)
      MacOSVersion.from_symbol(current_os_symbol)
    else
      return false
    end
    base_os = MacOSVersion.from_symbol(os_name)

    return current_os >= base_os if or_condition == :or_newer
    return current_os <= base_os if or_condition == :or_older

    current_os == base_os
  end

  sig { params(method_name: Symbol).returns(Symbol) }
  def self.condition_from_method_name(method_name)
    method_name.to_s.sub(/^on_/, "").to_sym
  end

  sig { params(base: T::Class[T.anything]).void }
  def self.setup_arch_methods(base)
    ARCH_OPTIONS.each do |arch|
      base.define_method(:"on_#{arch}") do |&block|
        @uses_on_system ||= T.let(OnSystem::UsesOnSystem.new, T.nilable(OnSystem::UsesOnSystem))
        @uses_on_system.send(:"#{arch}=", true)

        return unless OnSystem.arch_condition_met? OnSystem.condition_from_method_name(T.must(__method__))

        @called_in_on_system_block = T.let(true, T.nilable(T::Boolean))
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end

    base.define_method(:on_arch_conditional) do |arm: nil, intel: nil|
      @uses_on_system ||= T.let(OnSystem::UsesOnSystem.new, T.nilable(OnSystem::UsesOnSystem))
      @uses_on_system.arm = true if arm
      @uses_on_system.intel = true if intel

      if OnSystem.arch_condition_met? :arm
        arm
      elsif OnSystem.arch_condition_met? :intel
        intel
      end
    end
  end

  sig { params(base: T::Class[T.anything]).void }
  def self.setup_base_os_methods(base)
    BASE_OS_OPTIONS.each do |base_os|
      base.define_method(:"on_#{base_os}") do |&block|
        @uses_on_system ||= T.let(OnSystem::UsesOnSystem.new, T.nilable(OnSystem::UsesOnSystem))
        @uses_on_system.send(:"#{base_os}=", true)

        return unless OnSystem.os_condition_met? OnSystem.condition_from_method_name(T.must(__method__))

        @called_in_on_system_block = true
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end

    base.define_method(:on_system) do |linux, macos:, &block|
      @uses_on_system ||= T.let(OnSystem::UsesOnSystem.new, T.nilable(OnSystem::UsesOnSystem))
      @uses_on_system.linux = true
      @uses_on_system.macos = true

      raise ArgumentError, "The first argument to `on_system` must be `:linux`" if linux != :linux

      os_version, or_condition = if macos.to_s.include?("_or_")
        macos.to_s.split(/_(?=or_)/).map(&:to_sym)
      else
        [macos.to_sym, nil]
      end

      comparator = OnSystem.comparator_from_or_condition(or_condition)
      @uses_on_system.macos_requirements << MacOSRequirement.new([os_version], comparator:)
      return if !OnSystem.os_condition_met?(os_version, or_condition) && !OnSystem.os_condition_met?(:linux)

      @called_in_on_system_block = true
      result = block.call
      @called_in_on_system_block = false

      result
    end

    base.define_method(:on_system_conditional) do |macos: nil, linux: nil|
      @uses_on_system ||= T.let(OnSystem::UsesOnSystem.new, T.nilable(OnSystem::UsesOnSystem))
      @uses_on_system.macos = true if macos
      @uses_on_system.linux = true if linux

      if OnSystem.os_condition_met?(:macos) && macos.present?
        macos
      elsif OnSystem.os_condition_met?(:linux) && linux.present?
        linux
      end
    end
  end

  sig { params(base: T::Class[T.anything]).void }
  def self.setup_macos_methods(base)
    MacOSVersion::SYMBOLS.each_key do |os_name|
      base.define_method(:"on_#{os_name}") do |or_condition = nil, &block|
        @uses_on_system ||= T.let(OnSystem::UsesOnSystem.new, T.nilable(OnSystem::UsesOnSystem))
        @uses_on_system.macos = true

        os_condition = OnSystem.condition_from_method_name T.must(__method__)
        comparator = OnSystem.comparator_from_or_condition(or_condition)
        @uses_on_system.macos_requirements << MacOSRequirement.new([os_condition], comparator:)

        return unless OnSystem.os_condition_met?(os_condition, or_condition)

        @on_system_block_min_os = T.let(
          if or_condition == :or_older
            @called_in_on_system_block ? @on_system_block_min_os : MacOSVersion.new(HOMEBREW_MACOS_OLDEST_ALLOWED)
          else
            MacOSVersion.from_symbol(os_condition)
          end,
          T.nilable(MacOSVersion),
        )
        @called_in_on_system_block = true
        result = block.call
        @called_in_on_system_block = false

        result
      end
    end
  end

  sig { params(_base: T::Class[T.anything]).void }
  def self.included(_base)
    raise "Do not include `OnSystem` directly. Instead, include `OnSystem::MacOSAndLinux` or `OnSystem::MacOSOnly`"
  end

  module MacOSAndLinux
    sig { params(base: T::Class[T.anything]).void }
    def self.included(base)
      OnSystem.setup_arch_methods(base)
      OnSystem.setup_base_os_methods(base)
      OnSystem.setup_macos_methods(base)
    end
  end

  module MacOSOnly
    sig { params(base: T::Class[T.anything]).void }
    def self.included(base)
      OnSystem.setup_arch_methods(base)
      OnSystem.setup_macos_methods(base)
    end
  end
end
