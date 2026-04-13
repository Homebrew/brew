# typed: strict
# frozen_string_literal: true

require "cask/artifact/symlinked"

module Cask
  module Artifact
    class AppImage < Symlinked
      sig { params(target: T.any(String, Pathname)).returns(Pathname) }
      def resolve_target(target)
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
