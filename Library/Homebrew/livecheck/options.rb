# typed: strong
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # Options to modify livecheck's behavior. These primarily come from
    # `livecheck` blocks but they can also be set by livecheck at runtime.
    #
    # Option values use a `nil` default to indicate that the value has not been
    # set.
    class Options < T::Struct
      # Cookies for curl to use when making a request.
      prop :cookies, T.nilable(T::Hash[String, String])

      # Header(s) for curl to use when making a request.
      prop :header, T.nilable(T.any(String, T::Array[String]))

      # Whether to use brewed curl.
      prop :homebrew_curl, T.nilable(T::Boolean)

      # Form data to use when making a `POST` request.
      prop :post_form, T.nilable(T::Hash[Symbol, String])

      # JSON data to use when making a `POST` request.
      prop :post_json, T.nilable(T::Hash[Symbol, T.anything])

      # Referer for curl to use when making a request.
      prop :referer, T.nilable(String)

      # User agent for curl to use when making a request. Symbol arguments
      # should use a value supported by {Utils::Curl.curl_args}.
      prop :user_agent, T.nilable(T.any(String, Symbol))

      # Returns a `Hash` of options that are provided as arguments to `url`.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def url_options
        {
          cookies:,
          header:,
          homebrew_curl:,
          post_form:,
          post_json:,
          referer:,
          user_agent:,
        }
      end

      # Returns a `Hash` of all instance variables, using `String` keys.
      sig { returns(T::Hash[String, T.untyped]) }
      def to_hash
        T.let(serialize, T::Hash[String, T.untyped])
      end

      # Returns a `Hash` of all instance variables, using `Symbol` keys.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_h = to_hash.transform_keys(&:to_sym)

      # Returns a new object formed by merging `other` values with a copy of
      # `self`.
      #
      # `nil` values are removed from `other` before merging if it is an
      # `Options` object, as these are unitiailized values. This ensures that
      # existing values in `self` aren't unexpectedly overwritten with defaults.
      sig { params(other: T.any(Options, T::Hash[Symbol, T.untyped])).returns(Options) }
      def merge(other)
        return dup if other.empty?

        this_hash = to_h
        other_hash = other.is_a?(Options) ? other.to_h : other
        return dup if this_hash == other_hash

        new_options = this_hash.merge(other_hash)
        Options.new(**new_options)
      end

      # Merges values from `other` into `self` and returns `self`.
      #
      # `nil` values are removed from `other` before merging if it is an
      # `Options` object, as these are unitiailized values. This ensures that
      # existing values in `self` aren't unexpectedly overwritten with defaults.
      sig { params(other: T.any(Options, T::Hash[Symbol, T.untyped])).returns(Options) }
      def merge!(other)
        return self if other.empty?

        if other.is_a?(Options)
          return self if self == other

          other.instance_variables.each do |ivar|
            next if (v = T.let(other.instance_variable_get(ivar), Object)).nil?

            instance_variable_set(ivar, v)
          end
        else
          other.each do |k, v|
            cmd = :"#{k}="
            send(cmd, v) if respond_to?(cmd)
          end
        end

        self
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Options)

        @cookies == other.cookies &&
          @header == other.header &&
          @homebrew_curl == other.homebrew_curl &&
          @post_form == other.post_form &&
          @post_json == other.post_json &&
          @referer == other.referer &&
          @user_agent == other.user_agent
      end
      alias eql? ==

      # Whether the object has only default values.
      sig { returns(T::Boolean) }
      def empty? = to_hash.empty?

      # Whether the object has any non-default values.
      sig { returns(T::Boolean) }
      def present? = !empty?
    end
  end
end
