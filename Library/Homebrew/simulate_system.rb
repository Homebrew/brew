# typed: strict
# frozen_string_literal: true

require "macos_version"
require "utils/bottles"

module Homebrew
  # Helper module for simulating different system configurations.
  class SimulateSystem
    class << self
      sig { returns(T.nilable(Symbol)) }
      attr_reader :arch

      sig { returns(T.nilable(Symbol)) }
      attr_reader :os

      sig { returns(T::Hash[Symbol, Symbol]) }
      def arch_symbols
        { arm64: :arm, x86_64: :intel }.freeze
      end

      sig {
        type_parameters(:U).params(
          os:     Symbol,
          arch:   Symbol,
          _block: T.proc.returns(T.type_parameter(:U)),
        ).returns(T.type_parameter(:U))
      }
      def with(os: T.unsafe(nil), arch: T.unsafe(nil), &_block)
        raise ArgumentError, "At least one of `os` or `arch` must be specified." if !os && !arch

        old_os = self.os
        old_arch = self.arch

        begin
          self.os = os if os && os != current_os
          self.arch = arch if arch && arch != current_arch

          yield
        ensure
          @os = old_os
          @arch = old_arch
        end
      end

      sig {
        type_parameters(:U).params(
          tag:   Utils::Bottles::Tag,
          block: T.proc.returns(T.type_parameter(:U)),
        ).returns(T.type_parameter(:U))
      }
      def with_tag(tag, &block)
        raise ArgumentError, "Invalid tag: #{tag}" unless tag.valid_combination?

        with(os: tag.system, arch: tag.arch, &block)
      end

      sig { params(new_os: Symbol).void }
      def os=(new_os)
        os_options = [:macos, :linux, *MacOSVersion::SYMBOLS.keys]
        raise "Unknown OS: #{new_os}" unless os_options.include?(new_os)

        @os = T.let(new_os, T.nilable(Symbol))
      end

      sig { params(new_arch: Symbol).void }
      def arch=(new_arch)
        raise "New arch must be :arm or :intel" unless OnSystem::ARCH_OPTIONS.include?(new_arch)

        @arch = T.let(new_arch, T.nilable(Symbol))
      end

      sig { void }
      def clear
        @os = @arch = nil
      end

      sig { returns(T::Boolean) }
      def simulating_or_running_on_macos?
        [:macos, *MacOSVersion::SYMBOLS.keys].include?(os)
      end

      sig { returns(T::Boolean) }
      def simulating_or_running_on_linux?
        os == :linux
      end

      sig { returns(Symbol) }
      def current_arch
        @arch || Hardware::CPU.type
      end

      sig { returns(Symbol) }
      def current_os
        os || :generic
      end

      sig { returns(Utils::Bottles::Tag) }
      def current_tag
        Utils::Bottles::Tag.new(
          system: current_os,
          arch:   current_arch,
        )
      end
    end
  end
end

require "extend/os/simulate_system"
