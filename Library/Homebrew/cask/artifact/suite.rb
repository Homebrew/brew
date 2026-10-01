# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `suite` stanza.
    class Suite < Moved
      sig { override.returns(String) }
      def self.english_name
        "App Suite"
      end

      sig { override.returns(Symbol) }
      def self.dirmethod
        :appdir
      end
    end
  end
end
