# typed: true
# frozen_string_literal: true

module Cask
  class DSL
    # Class corresponding to the `version` stanza.
    #
    # @api private
    class Version < ::String
      DIVIDERS = {
        "." => :dots,
        "-" => :hyphens,
        "_" => :underscores,
      }.freeze

      DIVIDER_REGEX = /(#{DIVIDERS.keys.map { |v| Regexp.quote(v) }.join("|")})/

      MAJOR_MINOR_PATCH_REGEX = /^([^.,:]+)(?:.([^.,:]+)(?:.([^.,:]+))?)?/

      INVALID_CHARACTERS = /[^0-9a-zA-Z.,:\-_+ ]/

      class << self
        private

        def define_divider_methods(divider)
          define_divider_deletion_method(divider)
          define_divider_conversion_methods(divider)
        end

        def define_divider_deletion_method(divider)
          method_name = deletion_method_name(divider)
          define_method(method_name) do
            T.bind(self, Version)
            version { delete(divider) }
          end
        end

        def deletion_method_name(divider)
          "no_#{DIVIDERS[divider]}"
        end

        def define_divider_conversion_methods(left_divider)
          (DIVIDERS.keys - [left_divider]).each do |right_divider|
            define_divider_conversion_method(left_divider, right_divider)
          end
        end

        def define_divider_conversion_method(left_divider, right_divider)
          method_name = conversion_method_name(left_divider, right_divider)
          define_method(method_name) do
            T.bind(self, Version)
            version { gsub(left_divider, right_divider) }
          end
        end

        def conversion_method_name(left_divider, right_divider)
          "#{DIVIDERS[left_divider]}_to_#{DIVIDERS[right_divider]}"
        end
      end

      DIVIDERS.each_key do |divider|
        define_divider_methods(divider)
      end

      attr_reader :raw_version

      sig { params(raw_version: T.nilable(T.any(String, Symbol))).void }
      def initialize(raw_version)
        @raw_version = raw_version
        super(raw_version.to_s)

        invalid = invalid_characters
        raise TypeError, "#{raw_version} contains invalid characters: #{invalid.uniq.join}!" if invalid.present?
      end

      def invalid_characters
        return [] if raw_version.blank? || latest?

        raw_version.scan(INVALID_CHARACTERS)
      end

      sig { returns(T::Boolean) }
      def unstable?
        return false if latest?

        s = downcase.delete(".").gsub(/[^a-z\d]+/, "-")

        return true if s.match?(/(\d+|\b)(alpha|beta|preview|rc|dev|canary|snapshot)(\d+|\b)/i)
        return true if s.match?(/\A[a-z\d]+(-\d+)*-?(a|b|pre)(\d+|\b)/i)

        false
      end

      sig { returns(T::Boolean) }
      def latest?
        to_s == "latest"
      end

      # @api public
      sig { returns(T.self_type) }
      def major
        version { slice(MAJOR_MINOR_PATCH_REGEX, 1) }
      end

      # @api public
      sig { returns(T.self_type) }
      def minor
        version { slice(MAJOR_MINOR_PATCH_REGEX, 2) }
      end

      # @api public
      sig { returns(T.self_type) }
      def patch
        version { slice(MAJOR_MINOR_PATCH_REGEX, 3) }
      end

      # @api public
      sig { returns(T.self_type) }
      def major_minor
        version { [major, minor].reject(&:empty?).join(".") }
      end

      # @api public
      sig { returns(T.self_type) }
      def major_minor_patch
        version { [major, minor, patch].reject(&:empty?).join(".") }
      end

      # @api public
      sig { returns(T.self_type) }
      def minor_patch
        version { [minor, patch].reject(&:empty?).join(".") }
      end

      # @api public
      sig { returns(T::Array[Version]) } # Only top-level T.self_type is supported https://sorbet.org/docs/self-type
      def csv
        split(",").map { self.class.new(_1) }
      end

      # @api public
      sig { returns(T.self_type) }
      def before_comma
        version { split(",", 2).first }
      end

      # @api public
      sig { returns(T.self_type) }
      def after_comma
        version { split(",", 2).second }
      end

      # @api public
      sig { returns(T.self_type) }
      def no_dividers
        version { gsub(DIVIDER_REGEX, "") }
      end

      # @api public
      sig { params(separator: T.nilable(String)).returns(T.self_type) }
      def chomp(separator = nil)
        version { to_s.chomp(T.unsafe(separator)) }
      end

      private

      sig { returns(T.self_type) }
      def version
        return self if empty? || latest?

        self.class.new(yield)
      end
    end
  end
end
