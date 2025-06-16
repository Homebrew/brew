# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Cask
      # This cop checks for `version.before_comma` and `version.after_comma`.
      class UrlLegacyCommaSeparators < Url
        include OnUrlStanza
        extend AutoCorrector

        MSG_CSV = "Use `version.csv.first` instead of `version.before_comma` " \
                  "and `version.csv.second` instead of `version.after_comma`."

        sig { override.params(stanza: RuboCop::Cask::AST::Stanza).void }
        def on_url_stanza(stanza)
          return if stanza.stanza_node.block_type?

          url_node = T.cast(stanza.stanza_node, RuboCop::AST::SendNode).first_argument

          legacy_comma_separator_pattern = /version\.(before|after)_comma/

          url = url_node.source

          return unless url.match?(legacy_comma_separator_pattern)

          corrected_url = url.sub("before_comma", "csv.first")&.sub("after_comma", "csv.second")

          add_offense(url_node.loc.expression, message: format(MSG_CSV, url:)) do |corrector|
            corrector.replace(url_node.source_range, corrected_url)
          end
        end
      end
    end
  end
end
