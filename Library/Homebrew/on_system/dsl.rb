# typed: strict
# frozen_string_literal: true

require "on_system"

module OnSystem
  # Platform blocks common to formulae, resources, services and casks.
  module DSL
    ARCH_OPTIONS.each do |arch|
      define_method(:"on_#{arch}") do |&block|
        T.bind(self, DSL)
        mark_on_system_block
        with_on_system_block(:arch, &block) if OnSystem.arch_condition_met?(arch)
      end
    end

    MacOSVersion::SYMBOLS.each_key do |os_name|
      define_method(:"on_#{os_name}") do |or_condition = nil, &block|
        T.bind(self, DSL)
        mark_on_system_block(os: true)
        next unless OnSystem.os_condition_met?(os_name, or_condition)

        min_os = if or_condition == :or_older
          MacOSVersion.new(HOMEBREW_MACOS_OLDEST_ALLOWED)
        else
          MacOSVersion.from_symbol(os_name)
        end
        with_on_system_block(:os, min_os:, &block)
      end
    end

    # Whether the definition contains OS or architecture conditionals.
    sig { returns(T::Boolean) }
    def on_system_blocks_exist? = @on_system_blocks_exist == true

    sig { returns(T::Boolean) }
    def on_os_blocks_exist? = @on_os_blocks_exist == true

    sig { returns(T.nilable(MacOSVersion)) }
    attr_reader :on_system_block_min_os

    sig {
      type_parameters(:U)
        .params(arm: T.nilable(T.type_parameter(:U)), intel: T.nilable(T.type_parameter(:U)))
        .returns(T.nilable(T.type_parameter(:U)))
    }
    def on_arch_conditional(arm: nil, intel: nil)
      mark_on_system_block
      if OnSystem.arch_condition_met?(:arm)
        arm
      elsif OnSystem.arch_condition_met?(:intel)
        intel
      end
    end

    private

    sig { params(os: T::Boolean).void }
    def mark_on_system_block(os: false)
      @on_system_blocks_exist = T.let(true, T.nilable(TrueClass))
      @on_os_blocks_exist = T.let(true, T.nilable(TrueClass)) if os
    end

    sig { returns(T.nilable(Symbol)) }
    attr_reader :on_system_block

    sig { returns(T::Boolean) }
    def in_on_system_block? = !@on_system_block.nil?

    sig { returns(T::Boolean) }
    def in_on_os_block? = @on_system_block == :os

    sig {
      type_parameters(:U).params(
        scope:  T.nilable(Symbol),
        min_os: T.nilable(MacOSVersion),
        block:  T.proc.returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
    }
    def with_on_system_block(scope, min_os: nil, &block)
      previous_scope = @on_system_block
      previous_min_os = @active_min_os
      if min_os
        @active_min_os = T.let([previous_min_os, min_os].compact.max, T.nilable(MacOSVersion))
        # Audits read the effective minimum after the DSL has finished evaluating.
        @on_system_block_min_os = T.let(@active_min_os, T.nilable(MacOSVersion))
      end
      @on_system_block = T.let(scope, T.nilable(Symbol)) unless in_on_os_block?
      yield
    ensure
      @on_system_block = previous_scope
      @active_min_os = previous_min_os
    end
  end

  module MacOSOnly
    include DSL
  end

  module MacOSAndLinux
    include DSL

    BASE_OS_OPTIONS.each do |base_os|
      define_method(:"on_#{base_os}") do |&block|
        T.bind(self, MacOSAndLinux)
        mark_on_system_block(os: true)
        with_on_system_block(:os, &block) if OnSystem.os_condition_met?(base_os)
      end
    end

    sig {
      type_parameters(:U)
        .params(linux: Symbol, macos: Symbol, block: T.proc.returns(T.type_parameter(:U)))
        .returns(T.nilable(T.type_parameter(:U)))
    }
    def on_system(linux, macos:, &block)
      mark_on_system_block(os: true)
      Kernel.raise ArgumentError, "The first argument to `on_system` must be `:linux`" if linux != :linux

      os_version, _, or_condition = macos.to_s.partition(/_(?=or_)/)
      return if !OnSystem.os_condition_met?(os_version.to_sym, or_condition.presence&.to_sym) &&
                !OnSystem.os_condition_met?(:linux)

      with_on_system_block(:os, &block)
    end

    sig {
      type_parameters(:U).params(
        macos: T.nilable(T.all(Object, T.type_parameter(:U))),
        linux: T.nilable(T.all(Object, T.type_parameter(:U))),
      ).returns(T.nilable(T.type_parameter(:U)))
    }
    def on_system_conditional(macos: nil, linux: nil)
      mark_on_system_block
      if OnSystem.os_condition_met?(:macos) && macos.present?
        macos
      elsif OnSystem.os_condition_met?(:linux) && linux.present?
        linux
      end
    end
  end
end
