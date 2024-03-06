# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `prefpane` stanza.
    class Prefpane < Moved
      sig { returns(String) }
      def self.english_name
        "Preference Pane"
      end
    end
  end
end
