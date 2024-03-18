# typed: true
# frozen_string_literal: true

require "forwardable"
require "uri"

module RuboCop
  module Cop
    module Cask
      # This cop checks that a cask's homepage ends with a slash
      # if it does not have a path component.
      class HomepageUrlTrailingSlash < Base
        include OnHomepageStanza
        include HelperFunctions
        extend AutoCorrector

        MSG_NO_SLASH = "'%<url>s' must have a slash after the domain."

        def on_homepage_stanza(stanza)
          url_node = stanza.stanza_node.first_argument

          url = if url_node.dstr_type?
            # Remove quotes from interpolated string.
            url_node.source[1..-2]
          else
            url_node.str_content
          end

          return unless url&.match?(%r{^.+://[^/]+$})

          domain = URI(string_content(url_node, strip_dynamic: true)).host
          return if domain.blank?

          # This also takes URLs like 'https://example.org?path'
          # and 'https://example.org#path' into account.
          corrected_source = url_node.source.sub("://#{domain}", "://#{domain}/")

          add_offense(url_node.loc.expression, message: format(MSG_NO_SLASH, url:)) do |corrector|
            corrector.replace(url_node.source_range, corrected_source)
          end
        end
      end
    end
  end
end
