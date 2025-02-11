# typed: strict
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # Options to modify livecheck's behavior. These primarily come from
    # `livecheck` blocks but they can also be set by livecheck at runtime.
    class Options
      # Whether to use brewed curl.
      sig { returns(T.nilable(T::Boolean)) }
      attr_reader :homebrew_curl

      # Form data to use when making a `POST` request.
      sig { returns(T.nilable(T::Hash[T.any(String, Symbol), String])) }
      attr_reader :post_form

      # JSON data to use when making a `POST` request.
      sig { returns(T.nilable(T::Hash[T.any(String, Symbol), String])) }
      attr_reader :post_json

      # @param homebrew_curl whether to use brewed curl
      # @param post_form form data to use when making a `POST` request
      # @param post_json JSON data to use when making a `POST` request
      sig {
        params(
          homebrew_curl: T.nilable(T::Boolean),
          post_form:     T.nilable(T::Hash[T.any(String, Symbol), String]),
          post_json:     T.nilable(T::Hash[T.any(String, Symbol), String]),
        ).void
      }
      def initialize(homebrew_curl: nil, post_form: nil, post_json: nil)
        @homebrew_curl = homebrew_curl
        @post_form = post_form
        @post_json = post_json
      end

      # Returns a `Hash` of options that are provided as arguments to `url`.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def url_options
        {
          homebrew_curl:,
          post_form:,
          post_json:,
        }
      end

      # Returns a `Hash` of all instance variable values.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h
        {
          homebrew_curl:,
          post_form:,
          post_json:,
        }
      end

      # Returns a `Hash` of all instance variables, using `String` keys.
      sig { returns(T::Hash[String, T.untyped]) }
      def to_hash
        {
          "homebrew_curl" => @homebrew_curl,
          "post_form"     => @post_form,
          "post_json"     => @post_json,
        }
      end

      # Returns a new object formed by merging `other` values with a copy of
      # `self`.
      #
      # `nil` values are removed from `other` before merging if it is an
      # `Options` object, as these are unitiailized values. This ensures that
      # existing values in `self` aren't unexpectedly overwritten with defaults.
      sig { params(other: T.any(Options, T::Hash[Symbol, T.untyped])).returns(Options) }
      def merge(other)
        return dup if other.blank?

        this_hash = to_h
        other_hash = other.is_a?(Options) ? other.to_h.compact : other
        return dup if this_hash == other_hash

        new_options = this_hash.merge(other_hash)
        Options.new(**new_options)
      end

      sig { params(other: Options).returns(T::Boolean) }
      def ==(other)
        instance_of?(other.class) &&
          @homebrew_curl == other.homebrew_curl &&
          @post_form == other.post_form &&
          @post_json == other.post_json
      end
      alias eql? ==

      # Whether the object has only default values.
      sig { returns(T::Boolean) }
      def empty?
        @homebrew_curl.nil? && @post_form.nil? && @post_json.nil?
      end

      # Whether the object has any non-default values.
      sig { returns(T::Boolean) }
      def present?
        !@homebrew_curl.nil? || !@post_form.nil? || !@post_json.nil?
      end
    end
  end
end
