# typed: true
# frozen_string_literal: true

require "delegate"

require "requirements/macos_requirement"

module Cask
  class DSL
    # Class corresponding to the `depends_on` stanza.
    #
    # @api private
    class DependsOn < SimpleDelegator
      VALID_KEYS = Set.new([
        :formula,
        :cask,
        :macos,
        :arch,
      ]).freeze

      VALID_ARCHES = {
        intel:  { type: :intel, bits: 64 },
        # specific
        x86_64: { type: :intel, bits: 64 },
        arm64:  { type: :arm, bits: 64 },
      }.freeze

      attr_reader :arch, :cask, :formula, :macos

      def initialize
        super({})
        @cask ||= []
        @formula ||= []
      end

      def load(**pairs)
        pairs.each do |key, value|
          raise "invalid depends_on key: '#{key.inspect}'" unless VALID_KEYS.include?(key)

          __getobj__[key] = send(:"#{key}=", *value)
        end
      end

      def formula=(*args)
        @formula.concat(args)
      end

      def cask=(*args)
        @cask.concat(args)
      end

      sig { params(args: T.any(String, Symbol)).returns(T.nilable(MacOSRequirement)) }
      def macos=(*args)
        raise "Only a single 'depends_on macos' is allowed." if defined?(@macos)

        # workaround for https://github.com/sorbet/sorbet/issues/6860
        first_arg = args.first&.to_s

        begin
          @macos = if args.count > 1
            MacOSRequirement.new([args], comparator: "==")
          elsif MacOSVersion::SYMBOLS.key?(args.first)
            MacOSRequirement.new([args.first], comparator: "==")
          elsif (md = /^\s*(?<comparator><|>|[=<>]=)\s*:(?<version>\S+)\s*$/.match(first_arg))
            MacOSRequirement.new([T.must(md[:version]).to_sym], comparator: md[:comparator])
          elsif (md = /^\s*(?<comparator><|>|[=<>]=)\s*(?<version>\S+)\s*$/.match(first_arg))
            MacOSRequirement.new([md[:version]], comparator: md[:comparator])
          else # rubocop:disable Lint/DuplicateBranch
            MacOSRequirement.new([args.first], comparator: "==")
          end
        rescue MacOSVersion::Error, TypeError => e
          raise "invalid 'depends_on macos' value: #{e}"
        end
      end

      def arch=(*args)
        @arch ||= []
        arches = args.map do |elt|
          elt.to_s.downcase.sub(/^:/, "").tr("-", "_").to_sym
        end
        invalid_arches = arches - VALID_ARCHES.keys
        raise "invalid 'depends_on arch' values: #{invalid_arches.inspect}" unless invalid_arches.empty?

        @arch.concat(arches.map { |arch| VALID_ARCHES[arch] })
      end
    end
  end
end
