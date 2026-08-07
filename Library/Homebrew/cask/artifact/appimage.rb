# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    # Artifact corresponding to the `app_image` stanza.
    class AppImage < Symlinked
      sig { override.params(target: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(target, base_dir: nil)
        Pathname.new("#{config.appimagedir}/#{target}")
      end

      sig {
        override.params(
          force:    T::Boolean,
          adopt:    T::Boolean,
          command:  T.class_of(SystemCommand),
          _options: T.anything,
        ).void
      }
      def link(force: false, adopt: false, command: SystemCommand, **_options)
        super
        return if source.executable?

        if source.writable?
          FileUtils.chmod "+x", source
        else
          command.run!("chmod", args: ["+x", source], sudo: true)
        end
      end
    end
  end
end
