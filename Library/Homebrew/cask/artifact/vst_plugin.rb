# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `vst_plugin` stanza.
    #
    # @api private
    class VstPlugin < Moved
      sig { returns(String) }
      def self.english_name
        "VST Plugin"
      end
    end
  end
end
