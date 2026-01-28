# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `qlplugin` stanza.
    class Qlplugin < Moved
      sig { returns(String) }
      def self.english_name
        "Quick Look Plugin"
      end

      def install_phase(**options)
        super
        reload_quicklook(**options)
      end

      def uninstall_phase(**options)
        super
        reload_quicklook(**options)
      end

      private

      def reload_quicklook(command: nil, **_)
        command.run!("/usr/bin/qlmanage", args: ["-r"])
      end
    end
  end
end
