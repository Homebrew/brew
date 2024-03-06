# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `vst3_plugin` stanza.
    class Vst3Plugin < Moved
      sig { returns(String) }
      def self.english_name
        "VST3 Plugin"
      end
    end
  end
end
