# typed: strict
# frozen_string_literal: true

require "cask/artifact/relocated"

module Cask
  module Artifact
    # Superclass for all artifacts which are installed by symlinking them to the target location.
    class Symlinked < Relocated
      sig { returns(String) }
      def self.link_type_english_name
        "Symlink"
      end

      sig { returns(String) }
      def self.english_description
        "#{english_name} #{link_type_english_name}s"
      end

      sig {
        params(
          adopt:        T::Boolean,
          auto_updates: T.nilable(T::Boolean),
          force:        T::Boolean,
          verbose:      T::Boolean,
          predecessor:  T.nilable(Cask),
          overwrite:    T::Boolean,
          dry_run:      T::Boolean,
          command:      T.class_of(SystemCommand),
        ).void
      }
      def install_phase(adopt: false, auto_updates: false, force: false, verbose: false, predecessor: nil,
                        overwrite: false, dry_run: false, command: SystemCommand)
        link(force:, adopt:, overwrite:, dry_run:, command:)
      end

      sig {
        params(
          skip:      T::Boolean,
          force:     T::Boolean,
          verbose:   T::Boolean,
          successor: T.nilable(Cask),
          upgrade:   T::Boolean,
          reinstall: T::Boolean,
          dry_run:   T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def uninstall_phase(skip: false, force: false, verbose: false, successor: nil, upgrade: false,
                          reinstall: false, dry_run: false, command: SystemCommand)
        unlink(dry_run:, command:)
      end

      sig { returns(String) }
      def summarize_installed
        if target.symlink? && target.exist? && target.readlink.exist?
          "#{printable_target} -> #{target.readlink} (#{target.readlink.abv})"
        else
          string = if target.symlink?
            "#{printable_target} -> #{target.readlink}"
          else
            printable_target
          end

          Formatter.error(string, label: "Broken Link")
        end
      end

      # Whether the target is this cask's symlink, even if the source has since gone.
      sig { returns(T::Boolean) }
      def target_links_to_source?
        target.symlink? && (target.readlink == source || target.realpath == source.realpath)
      rescue => e
        odebug "Error checking whether #{target} links to #{source}: #{e}"
        false
      end

      # What linking would do to the current target without changing anything:
      # `:link`, `:overwrite`, `:already_linked`, `:skip_formula` or `:conflict`.
      sig { params(force: T::Boolean, adopt: T::Boolean, overwrite: T::Boolean).returns(Symbol) }
      def link_action(force: false, adopt: false, overwrite: false)
        return :link unless target.exist?

        if overwrite ||
           ((force || adopt) && target.symlink? &&
            (target_links_to_source? || target.realpath.to_s.start_with?("#{cask.caskroom_path}/")))
          :overwrite
        elsif target_links_to_source?
          :already_linked
        elsif conflicting_formula
          :skip_formula
        else
          :conflict
        end
      end

      private

      sig {
        overridable.params(
          force:     T::Boolean,
          adopt:     T::Boolean,
          overwrite: T::Boolean,
          dry_run:   T::Boolean,
          command:   T.class_of(SystemCommand),
        ).void
      }
      def link(force: false, adopt: false, overwrite: false, dry_run: false, command: SystemCommand)
        if !dry_run && !source.exist?
          raise CaskError,
                "It seems the #{self.class.link_type_english_name.downcase} " \
                "source '#{source}' is not there."
        end

        message = "It seems there is already #{self.class.english_article} " \
                  "#{self.class.english_name} at '#{target}'"
        case link_action(force:, adopt:, overwrite:)
        when :overwrite
          if dry_run
            puts target
            return
          end

          opoo "#{message}; overwriting."
          Utils.gain_permissions_remove(target, command:)
        when :already_linked
          ohai "#{self.class.english_name} '#{source.basename}' is already linked to '#{target}'" unless dry_run
          return
        when :skip_formula
          opoo "#{message} from formula #{conflicting_formula}; skipping link."
          return
        when :conflict
          raise CaskError, "#{message}."
        end

        if dry_run
          # `ln --force` also replaces broken symlinks.
          puts target if !overwrite || target.symlink?
          return
        end

        ohai "Linking #{self.class.english_name} '#{source.basename}' to '#{target}'"
        create_filesystem_link(command)
      end

      sig { params(dry_run: T::Boolean, command: T.class_of(SystemCommand)).void }
      def unlink(dry_run: false, command: SystemCommand)
        return unless target.symlink?

        if (formula = conflicting_formula)
          odebug "#{target} is from formula #{formula}; skipping unlink."
          return
        end

        if dry_run
          puts target
          return
        end

        ohai "Unlinking #{self.class.english_name} '#{target}'"
        Utils.gain_permissions_remove(target, command:)
      end

      sig { params(command: T.class_of(SystemCommand)).void }
      def create_filesystem_link(command)
        Utils.gain_permissions_mkpath(target.dirname, command:)

        command.run! "/bin/ln", args: ["--no-dereference", "--force", "--symbolic", source, target],
                                sudo: nil
      end

      # Check if the target file is a symlink that originates from a formula
      # with the same name as this cask, indicating a potential conflict
      sig { returns(T.nilable(String)) }
      def conflicting_formula
        if target.symlink? && target.exist? &&
           (match = target.realpath.to_s.match(%r{^#{HOMEBREW_CELLAR}/(?<formula>[^/]+)/}o))
          match[:formula]
        end
      rescue => e
        # If we can't determine the realpath or any other error occurs,
        # don't treat it as a conflicting formula file
        odebug "Error checking for conflicting formula file: #{e}"
        nil
      end
    end
  end
end

require "extend/os/cask/artifact/symlinked"
