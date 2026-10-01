# typed: strict
# frozen_string_literal: true

require "cask/artifact/moved"

module Cask
  module Artifact
    # Artifact corresponding to the `app_image` stanza.
    class AppImage < Moved
      sig { override.params(target: T.any(String, Pathname), base_dir: T.nilable(Pathname)).returns(Pathname) }
      def resolve_target(target, base_dir: nil)
        Pathname.new("#{config.appimagedir}/#{target}")
      end

      sig {
        override.params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          successor:    T.nilable(Cask),
          reinstall:    T::Boolean,
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        successor: nil, reinstall: false, command: SystemCommand)
        super

        return if target.executable?

        if target.writable?
          FileUtils.chmod "+x", target
        else
          command.run!("chmod", args: ["+x", target], sudo: nil)
        end
      end

      sig {
        override.params(
          skip:      T::Boolean,
          force:     T::Boolean,
          adopt:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def uninstall_phase(skip: false, force: false, adopt: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, command: SystemCommand)
        # Migration shim for the `Symlinked` -> `Moved` transition.
        # Old installs have the real AppImage in the versioned Caskroom `source`
        # and a symlink at `target` pointing back to it,
        # which `Moved#move_back` cannot reverse
        # (a non-forced uninstall errors; a skipping one leaves the target behind).
        # The old layout is identified by `target` being that back-symlink
        # (in the new layout, `target` is the real file),
        # regardless of whether `source` still exists:
        # the very breakage this stanza fixes
        # is a self-updater having already deleted the versioned `source`,
        # leaving `target` dangling. Reverse the old layout directly instead.
        # This can be removed once pre-transition installs have aged out.
        if target.symlink? && target.dirname.join(target.readlink) == source
          Utils.gain_permissions_remove(target, command:)
          # Preserve `source` during an upgrade
          # so that it is captured in the staged-directory backup
          # that `revert_upgrade` restores (and reinstalls from)
          # if the new install fails;
          # a successful upgrade purges that backup afterwards.
          Utils.gain_permissions_remove(source, command:) unless upgrade
          return
        end

        super
      end
    end
  end
end
