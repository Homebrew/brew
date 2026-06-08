# typed: strict
# frozen_string_literal: true

require "delegate"

require "requirements/macos_requirement"
require "requirements/linux_requirement"
require "utils/output"

module Cask
  class DSL
    # Class corresponding to the `depends_on` stanza.
    class DependsOn < SimpleDelegator
      include ::Utils::Output::Mixin

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
        @macos_bare_set_top_level = T.let(false, T::Boolean)
        @macos_version_set_top_level = T.let(false, T::Boolean)
        @maximum_macos_set_top_level = T.let(false, T::Boolean)
        @linux_set_top_level = T.let(false, T::Boolean)
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
        ).void
      }
      def load(pairs, set_in_block: false)
        pairs.each do |key, value|
          raise "invalid depends_on key: '#{key.inspect}'" unless VALID_KEYS.include?(key)

          previous_macos = @macos if key == :macos
          __getobj__[key] = case key
          when :macos, :maximum_macos
            send(:"#{key}=", *value, set_in_block:)
          else
            send(:"#{key}=", *value)
          end
          record_os_requirement(key, set_in_block:)
          next if key != :macos
          next if value != :any
          next unless previous_macos&.version_specified?

          @macos = previous_macos
          __getobj__[key] = previous_macos
        end
      end

      sig { params(args: String).returns(T::Array[String]) }
      def formula=(*args)
        formula.concat(args)
      end

      sig { params(args: String).returns(T::Array[String]) }
      def cask=(*args)
        cask.concat(args)
      end

      sig { params(args: T.any(String, Symbol), set_in_block: T::Boolean).returns(T.nilable(MacOSRequirement)) }
      def macos=(*args, set_in_block: false)
        @macos = MacOSRequirement.parse(args, comparator: ">=")
      rescue MacOSVersion::Error, TypeError => e
        raise "invalid 'depends_on macos' value: #{e}"
      end

      sig { params(args: T.any(String, Symbol), set_in_block: T::Boolean).returns(T.nilable(MacOSRequirement)) }
      def maximum_macos=(*args, set_in_block: false)
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

      sig { params(args: T.any(String, Symbol)).returns(T.nilable(LinuxRequirement)) }
      def linux=(*args)
        raise "Only a single 'depends_on linux' is allowed." if @linux
        raise "invalid 'depends_on linux' value: #{args.first.inspect}" if args.first != :any

        @linux = LinuxRequirement.new
      end

      sig { params(args: Symbol).returns(T::Array[T::Hash[Symbol, T.any(Symbol, Integer)]]) }
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

      sig { returns(T::Boolean) }
      def requires_macos?
        @macos_bare_set_top_level || @macos_version_set_top_level || @maximum_macos_set_top_level
      end

      sig { returns(T::Boolean) }
      def requires_linux? = @linux_set_top_level

      sig { params(key: Symbol, set_in_block: T::Boolean).void }
      def record_os_requirement(key, set_in_block:)
        case key
        when :macos
          macos = @macos
          raise "invalid 'depends_on macos' value" unless macos

          record_macos_requirement(macos, set_in_block:)
        when :maximum_macos
          maximum_macos = @maximum_macos
          raise "invalid 'depends_on maximum_macos' value" unless maximum_macos

          record_macos_requirement(maximum_macos, set_in_block:)
        when :linux
          return if set_in_block
          raise "`depends_on :linux` cannot be combined with `depends_on macos:`" if requires_macos?

          @linux_set_top_level = true
        end
      end

      sig { params(requirement: MacOSRequirement, set_in_block: T::Boolean).void }
      def record_macos_requirement(requirement, set_in_block:)
        return if set_in_block

        raise "`depends_on :linux` cannot be combined with `depends_on macos:`" if requires_linux?

        if !requirement.version_specified?
          raise "`depends_on :macos` cannot be combined with another macOS `depends_on`" if @macos_bare_set_top_level

          if @macos_version_set_top_level || @maximum_macos_set_top_level
            odeprecated "`depends_on :macos` with `depends_on macos:`"
          end

          @macos_bare_set_top_level = true
        elsif requirement.comparator == "<="
          odeprecated "`depends_on :macos` with `depends_on maximum_macos:`" if @macos_bare_set_top_level

          if @maximum_macos_set_top_level
            raise "`depends_on maximum_macos:` cannot be combined with another macOS `depends_on`"
          end

          @maximum_macos_set_top_level = true
        else
          odeprecated "`depends_on :macos` with `depends_on macos:`" if @macos_bare_set_top_level

          if @macos_version_set_top_level
            raise "`depends_on macos:` cannot be combined with another macOS `depends_on`"
          end

          @macos_version_set_top_level = true
        end
      end
    end
  end
end
