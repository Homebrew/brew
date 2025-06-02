# frozen_string_literal: true

module Bundler
  class Source
    class Rubygems
      class Remote
        attr_reader :uri, :anonymized_uri, :original_uri

        def initialize(uri)
          orig_uri = uri
          uri = Bundler.settings.mirror_for(uri)
          @original_uri = orig_uri if orig_uri != uri
          fallback_auth = Bundler.settings.credentials_for(uri)

          @uri = apply_auth(uri, fallback_auth).freeze
          @anonymized_uri = remove_auth(@uri).freeze
        end

        # @return [String] A slug suitable for use as a cache key for this
        #         remote.
        #
        def cache_slug
          @cache_slug ||= begin
            return nil unless SharedHelpers.md5_available?

            cache_uri = original_uri || uri

            host = cache_uri.to_s.start_with?("file://") ? nil : cache_uri.host

            uri_parts = [host, cache_uri.user, cache_uri.port, cache_uri.path]
            uri_digest = SharedHelpers.digest(:MD5).hexdigest(uri_parts.compact.join("."))

            uri_parts[-1] = uri_digest
            uri_parts.compact.join(".")
          end
        end

        def to_s
          "rubygems remote at #{anonymized_uri}"
        end

        private

        def apply_auth(uri, auth)
          if auth && uri.userinfo.nil?
            uri = uri.dup
            uri.userinfo = auth
          end

          uri
        rescue Bundler::URI::InvalidComponentError
          error_message = "Please CGI escape your usernames and passwords before " \
                          "setting them for authentication."
          raise HTTPError.new(error_message)
        end

        def remove_auth(uri)
          if uri.userinfo
            uri = uri.dup
            uri.user = uri.password = nil
          end

          uri
        end
      end
    end
  end
end
