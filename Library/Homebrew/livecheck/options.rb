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
      # Whether to request a compressed response.
      prop :compressed, T.nilable(FalseClass)

      # Cookies for curl to use when making a request.
      prop :cookies, T.nilable(T::Hash[String, String])

      # Header(s) for curl to use when making a request.
      prop :header, T.nilable(T.any(String, T::Array[String]))

      # Whether to use brewed curl.
      prop :homebrew_curl, T.nilable(TrueClass)

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
          compressed:,
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
      # `nil` values from `other` are skipped, as these are uninitialized. This
      # ensures that existing values in `self` aren't unexpectedly overwritten
      # by defaults.
      sig { params(other: Options).returns(Options) }
      def merge(other) = deep_dup.merge!(other)

      # Merges values from `other` into `self` and returns `self`.
      #
      # `nil` values from `other` are skipped, as these are uninitialized. This
      # ensures that existing values in `self` aren't unexpectedly overwritten
      # by defaults.
      sig { params(other: Options).returns(Options) }
      def merge!(other)
        return self if other.empty?

        # These options are mutually exclusive, so we can't know which should be
        # used when `other` has both
        other_post_form = other.post_form
        other_post_json = other.post_json
        if other_post_form && other_post_json
          raise ArgumentError, "Cannot merge provided options using both `post_form` and `post_json`"
        end

        return self if self == other

        other.instance_variables.each do |ivar|
          next if (val = T.let(other.instance_variable_get(ivar), Object)).nil?

          public_send(:"#{ivar.to_s.delete_prefix("@")}=", val.deep_dup)
        end

        # Merging one of these options should unset the opposite value in `self`
        if !other_post_form.nil?
          self.post_json = nil
        elsif !other_post_json.nil?
          self.post_form = nil
        end

        self
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Options)

        @compressed == other.compressed &&
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
