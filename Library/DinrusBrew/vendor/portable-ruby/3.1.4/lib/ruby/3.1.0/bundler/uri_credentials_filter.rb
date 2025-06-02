# frozen_string_literal: true

module Bundler
  module URICredentialsFilter
    module_function

    def credential_filtered_uri(uri_to_anonymize)
      return uri_to_anonymize if uri_to_anonymize.nil?
      uri = uri_to_anonymize.dup
      if uri.is_a?(String)
        return uri if File.exist?(uri)

        require_relative "vendored_uri"
        uri = Bundler::URI(uri)
      end

      if uri.userinfo
        # oauth authentication
        if uri.password == "x-oauth-basic" || uri.password == "x"
          # URI as string does not display with password if no user is set
          oauth_designation = uri.password
          uri.user = oauth_designation
        end
        uri.password = nil
      end
      return uri.to_s if uri_to_anonymize.is_a?(String)
      uri
    rescue Bundler::URI::InvalidURIError # uri is not canonical uri scheme
      uri
    end

    def credential_filtered_string(str_to_filter, uri)
      return str_to_filter if uri.nil? || str_to_filter.nil?
      str_with_no_credentials = str_to_filter.dup
      anonymous_uri_str = credential_filtered_uri(uri).to_s
      uri_str = uri.to_s
      if anonymous_uri_str != uri_str
        str_with_no_credentials = str_with_no_credentials.gsub(uri_str, anonymous_uri_str)
      end
      str_with_no_credentials
    end
  end
end
