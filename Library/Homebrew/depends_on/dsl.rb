# typed: strict
# frozen_string_literal: true

require "requirements/macos_requirement"
require "requirements/linux_requirement"
require "utils/output"

module DependsOn
  # Track platform support and validate OS requirements for the active architecture.
  module DSL
    sig { returns(T::Boolean) }
    def requires_macos? = @required_os == :macos

    sig { returns(T::Boolean) }
    def requires_linux? = @required_os == :linux

    sig { returns(T::Boolean) }
    def depends_on_macos_set_top_level? = @top_level_macos.present?

    sig { returns(T::Boolean) }
    def depends_on_linux_set_top_level? = @linux_set_top_level == true

    sig { returns(T::Boolean) }
    def depends_on_macos_set_in_block? = @macos_set_in_block == true
    alias depends_on_macos_set_in_block depends_on_macos_set_in_block?

    private

    sig { params(requirement: Requirement, set_in_block: T::Boolean, os_scoped: T::Boolean).void }
    def record_os_requirement(requirement, set_in_block:, os_scoped:)
      case requirement
      when MacOSRequirement
        @macos_set_in_block = T.let(true, T.nilable(TrueClass)) if set_in_block
        os = :macos
      when LinuxRequirement
        os = :linux
      else
        return
      end
      return if os_scoped

      if @required_os && @required_os != os
        Kernel.raise ArgumentError, "`depends_on :linux` cannot be combined with `depends_on macos:`"
      end

      unless set_in_block
        if requirement.is_a?(MacOSRequirement)
          record_top_level_macos(requirement)
        elsif depends_on_linux_set_top_level?
          Kernel.raise ArgumentError, "Only a single 'depends_on linux' is allowed."
        else
          @linux_set_top_level = T.let(true, T.nilable(TrueClass))
        end
      end
      @required_os = T.let(os, T.nilable(Symbol))
    end

    sig { params(requirement: MacOSRequirement).void }
    def record_top_level_macos(requirement)
      stanza = if !requirement.version_specified?
        ":macos"
      elsif requirement.comparator == "<="
        "maximum_macos:"
      else
        "macos:"
      end
      previous = @top_level_macos || []
      if previous.include?(stanza)
        Kernel.raise ArgumentError, "`depends_on #{stanza}` cannot be combined with another macOS `depends_on`"
      end
      if previous.any? && (stanza == ":macos" || previous.include?(":macos"))
        versioned = if stanza == ":macos"
          previous.fetch(0)
        else
          stanza
        end
        Utils::Output.odisabled "`depends_on :macos` with `depends_on #{versioned}`",
                                "`depends_on :macos` with `depends_on #{versioned}` inside an `on_macos` block"
      end

      @top_level_macos = T.let([*previous, stanza].freeze, T.nilable(T::Array[String]))
    end
  end
end
