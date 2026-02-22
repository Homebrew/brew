# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `qlplugin` stanza.
    class Qlplugin < Moved
      sig { override.returns(String) }
      def self.english_name
        "Quick Look Plugin"
      end

      sig { override.params(command: T.class_of(SystemCommand), options: T.anything).void }
      def install_phase(command:, **options)
        super
        reload_quicklook(command:, **options)
      end

      sig { override.params(command: T.class_of(SystemCommand), options: T.anything).void }
      def uninstall_phase(command:, **options)
        super
        reload_quicklook(command:, **options)
      end

      private

      sig { params(command: T.class_of(SystemCommand), _options: T.anything).void }
      def reload_quicklook(command:, **_options)
        command.run!("/usr/bin/qlmanage", args: ["-r"])
      end
    end
  end
end
