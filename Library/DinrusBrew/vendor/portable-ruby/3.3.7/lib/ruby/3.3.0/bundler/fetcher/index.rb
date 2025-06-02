# frozen_string_literal: true

require_relative "base"

module Bundler
  class Fetcher
    class Index < Base
      def specs(_gem_names)
        Bundler.rubygems.fetch_all_remote_specs(remote, gem_remote_fetcher)
      rescue Gem::RemoteFetcher::FetchError => e
        case e.message
        when /certificate verify failed/
          raise CertificateFailureError.new(display_uri)
        when /401/
          raise BadAuthenticationError, remote_uri if remote_uri.userinfo
          raise AuthenticationRequiredError, remote_uri
        when /403/
          raise AuthenticationForbiddenError, remote_uri
        else
          raise HTTPError, "Could not fetch specs from #{display_uri} due to underlying error <#{e.message}>"
        end
      end
    end
  end
end
