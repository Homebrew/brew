# typed: strict
# frozen_string_literal: true

require "forwardable"
require "uri"
require "rubocops/shared/homepage_helper"

module RuboCop
  module Cop
    module Cask
      # This cop audits the `homepage` URL in casks.
      class HomepageUrlStyling < Base
        include OnHomepageStanza
        include HelperFunctions
        include HomepageHelper
        extend AutoCorrector

        MSG_NO_SLASH = "'%<url>s' must have a slash after the domain."

        sig { params(stanza: RuboCop::Cask::AST::Stanza).void }
        def on_homepage_stanza(stanza)
          @name = T.let(cask_block&.header&.cask_token, T.nilable(String))
          desc_call = T.cast(stanza.stanza_node, RuboCop::AST::SendNode)
          url_node = desc_call.first_argument

          url = if url_node.dstr_type?
            # Remove quotes from interpolated string.
            url_node.source[1..-2]
          else
            url_node.str_content
          end

          audit_homepage(:cask, url, desc_call, url_node)

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
