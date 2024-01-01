# typed: true
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `mdimporter` stanza.
    #
    # @api private
    class Mdimporter < Moved
      sig { returns(String) }
      def self.english_name
        "Spotlight metadata importer"
      end

      def install_phase(**options)
        super(**options)
        reload_spotlight(**options)
      end

      private

      def reload_spotlight(command: nil, **_)
        command.run!("/usr/bin/mdimport", args: ["-r", target])
      end
    end
  end
end
