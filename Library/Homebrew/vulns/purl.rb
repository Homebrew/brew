# typed: strict
# frozen_string_literal: true

module Homebrew
  module Vulns
    # A package URL per https://github.com/package-url/purl-spec.
    #
    # Minimal builder for the registry types Homebrew derives from formula
    # source URLs. Applies the spec's per-type name normalisation and RFC 3986
    # percent-encoding when serialised. Parsing, qualifiers and subpath are
    # intentionally omitted.
    class Purl
      sig { returns(String) }
      attr_reader :type, :name

      sig { returns(T.nilable(String)) }
      attr_reader :namespace, :version

      sig {
        params(type: String, name: String, namespace: T.nilable(String), version: T.nilable(String)).void
      }
      def initialize(type:, name:, namespace: nil, version: nil)
        raise ArgumentError, "type is required" if type.empty?
        raise ArgumentError, "name is required" if name.empty?

        @type = T.let(type.downcase.freeze, String)
        namespace = nil if namespace && namespace.empty?
        namespace, name = self.class.normalize(@type, namespace, name)
        @namespace = T.let(namespace && -namespace, T.nilable(String))
        @name = T.let(-name, String)
        version = nil if version && version.empty?
        @version = T.let(version && -version, T.nilable(String))
      end

      sig { returns(String) }
      def to_s
        purl = "pkg:#{@type}/"
        if @namespace
          purl << @namespace.split("/").reject(&:empty?).map { |s| self.class.encode(s) }.join("/")
          purl << "/"
        end
        purl << self.class.encode(@name)
        purl << "@#{self.class.encode(@version)}" if @version
        purl.freeze
      end

      sig { params(other: T.anything).returns(T::Boolean) }
      def ==(other)
        case other
        when Purl
          type == other.type && namespace == other.namespace &&
            name == other.name && version == other.version
        else false
        end
      end
      alias eql? ==

      sig { returns(Integer) }
      def hash
        [type, namespace, name, version].hash
      end

      # Percent-encode a single purl component. The spec permits the RFC 3986
      # unreserved set plus `:` unencoded; `+` for space is forbidden so
      # `URI.encode_www_form_component` is unsuitable.
      sig { params(component: String).returns(String) }
      def self.encode(component)
        component.b.gsub(/[^A-Za-z0-9\-._~:]/n) { |c| format("%%%02X", c.ord) }
      end

      # Per-type normalisation from purl-spec PURL-TYPES.rst for the types we emit.
      sig {
        params(type: String, namespace: T.nilable(String), name: String)
          .returns([T.nilable(String), String])
      }
      def self.normalize(type, namespace, name)
        case type
        when "pypi"
          [namespace, name.downcase.tr("_", "-")]
        when "hex"
          [namespace&.downcase, name.downcase]
        when "cpan"
          [namespace&.upcase, name]
        else
          [namespace, name]
        end
      end
    end
  end
end
