# typed: strict
# frozen_string_literal: true

require "rubocops/shared/url_helper"

module RuboCop
  module Cop
    module Cask
      # This cop checks that a cask's `url` stanza is formatted correctly.
      #
      # ### Example
      #
      # ```ruby
      # # bad
      # url "https://example.com/download/foo.dmg",
      #     verified: "https://example.com/download"
      #
      # # good
      # url "https://example.com/download/foo.dmg",
      #     verified: "example.com/download/"
      # ```
      class Url < Base
        extend AutoCorrector
        include OnUrlStanza
        include UrlHelper

        sig { params(stanza: RuboCop::Cask::AST::Stanza).void }
        def on_url_stanza(stanza)
          if stanza.stanza_node.block_type?
            if cask_tap == "homebrew-cask"
              add_offense(stanza.stanza_node, message: 'Do not use `url "..." do` blocks in Homebrew/homebrew-cask.')
            end
            return
          end

          stanza_node = T.cast(stanza.stanza_node, RuboCop::AST::SendNode)
          url_stanza = stanza_node.first_argument
          hash_node = stanza_node.last_argument

          audit_url(:cask, [stanza.stanza_node], [], livecheck_url: false)

          return unless hash_node.hash_type?

          unless stanza_node.source.match?(/",\n      *\w+:/)
            add_offense(
              stanza_node.source_range,
              message: "Keyword URL parameter should be on a new indented line.",
            ) do |corrector|
              corrector.replace(stanza_node.source_range, stanza_node.source.gsub(/",\s*/, "\",\n      "))
            end
          end

          hash_node.each_pair do |key_node, value_node|
            next if key_node.source != "verified"
            next unless value_node.str_type?

            if value_node.source.start_with?(%r{^"https?://})
              add_offense(
                value_node.source_range,
                message: "Verified URL parameter value should not contain a URL scheme.",
              ) do |corrector|
                corrector.replace(value_node.source_range, value_node.source.gsub(%r{^"https?://}, "\""))
              end
            end

            # Skip if the URL and the verified value are the same.
            next if value_node.source == url_stanza.source.gsub(%r{^"https?://}, "\"")
            # Skip if the URL has two path components, e.g. `https://github.com/google/fonts.git`.
            next if url_stanza.source.gsub(%r{^"https?://}, "\"").count("/") == 2
            # Skip if the verified value ends with a slash.
            next if value_node.str_content.end_with?("/")

            add_offense(
              value_node.source_range,
              message: "Verified URL parameter value should end with a /.",
            ) do |corrector|
              corrector.replace(value_node.source_range, value_node.source.gsub(/"$/, "/\""))
            end
          end
        end
      end
    end
  end
end
