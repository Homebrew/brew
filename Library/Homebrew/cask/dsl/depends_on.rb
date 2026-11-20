# typed: strict
# frozen_string_literal: true

require "delegate"

require "depends_on/dsl"

module Cask
  class DSL
    # Class corresponding to the `depends_on` stanza.
    class DependsOn < SimpleDelegator
      include ::DependsOn::DSL

      VALID_KEYS = T.let(Set.new([
        :formula,
        :cask,
        :macos,
        :maximum_macos,
        :linux,
        :arch,
      ]).freeze, T::Set[Symbol])

      VALID_ARCHES = T.let({
        intel:  { type: :intel, bits: 64 },
        # specific
        x86_64: { type: :intel, bits: 64 },
        arm64:  { type: :arm, bits: 64 },
      }.freeze, T::Hash[Symbol, T::Hash[Symbol, T.any(Symbol, Integer)]])

      sig { returns(T.nilable(T::Array[T::Hash[Symbol, T.any(Symbol, Integer)]])) }
      attr_reader :arch

      sig { returns(T.nilable(MacOSRequirement)) }
      attr_reader :macos

      sig { returns(T.nilable(MacOSRequirement)) }
      attr_reader :maximum_macos

      sig { returns(T.nilable(LinuxRequirement)) }
      attr_reader :linux

      sig { void }
      def initialize
        super({})
        @arch = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, T.any(Symbol, Integer)]]))
        @cask = T.let(nil, T.nilable(T::Array[String]))
        @formula = T.let(nil, T.nilable(T::Array[String]))
        @macos = T.let(nil, T.nilable(MacOSRequirement))
        @maximum_macos = T.let(nil, T.nilable(MacOSRequirement))
        @linux = T.let(nil, T.nilable(LinuxRequirement))
      end

      sig { returns(T::Array[String]) }
      def cask
        @cask ||= []
      end

      sig { returns(T::Array[String]) }
      def formula
        @formula ||= []
      end

      sig {
        params(
          pairs:        T::Hash[Symbol, T.any(String, Symbol, T::Array[T.any(String, Symbol)])],
          set_in_block: T::Boolean,
          os_scoped:    T::Boolean,
        ).void
      }
      def load(pairs, set_in_block: false, os_scoped: false)
        pairs.each do |key, value|
          raise "invalid depends_on key: '#{key.inspect}'" unless VALID_KEYS.include?(key)

          previous_macos = @macos if key == :macos
          public_send(:"#{key}=", *value)
          dependency = public_send(key)
          record_os_requirement(dependency, set_in_block:, os_scoped:) if dependency.is_a?(Requirement)
          __getobj__[key] = dependency
          next if key != :macos
          next if value != :any
          next unless previous_macos&.version_specified?

          @macos = previous_macos
          __getobj__[key] = previous_macos
        end
      end

      sig { params(args: String).void }
      def formula=(*args)
        formula.concat(args)
      end

      sig { params(args: String).void }
      def cask=(*args)
        cask.concat(args)
      end

      sig { params(args: T.any(String, Symbol)).void }
      def macos=(*args)
        @macos = MacOSRequirement.parse(args, comparator: ">=")
      rescue MacOSVersion::Error, TypeError => e
        raise "invalid 'depends_on macos' value: #{e}"
      end

      sig { params(args: T.any(String, Symbol)).void }
      def maximum_macos=(*args)
        raise "invalid 'depends_on maximum_macos' value: only a single macOS version is allowed" if args.count != 1

        maximum_macos = begin
          MacOSRequirement.parse(args, comparator: "<=")
        rescue MacOSVersion::Error, TypeError => e
          raise "invalid 'depends_on maximum_macos' value: #{e}"
        end
        if maximum_macos.comparator != "<="
          raise "invalid 'depends_on maximum_macos' value: must use the '<=' comparator"
        end

        @maximum_macos = maximum_macos
      end

      sig { params(args: T.any(String, Symbol)).void }
      def linux=(*args)
        raise "invalid 'depends_on linux' value: #{args.first.inspect}" if args.first != :any

        @linux = LinuxRequirement.new
      end

      sig { params(args: Symbol).void }
      def arch=(*args)
        @arch ||= []
        arches = args.map do |elt|
          elt.to_s.downcase.sub(/^:/, "").tr("-", "_").to_sym
        end
        invalid_arches = arches - VALID_ARCHES.keys
        raise "invalid 'depends_on arch' values: #{invalid_arches.inspect}" unless invalid_arches.empty?

        @arch.concat(arches.map { |arch| VALID_ARCHES.fetch(arch) })
      end

      sig { returns(T::Boolean) }
      def empty? = T.let(__getobj__, T::Hash[Symbol, T.untyped]).empty?

      sig { returns(T::Boolean) }
      def present? = !empty?
    end
  end
end
