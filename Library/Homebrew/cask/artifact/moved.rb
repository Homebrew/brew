# typed: true
# frozen_string_literal: true

require "cask/artifact/relocated"
require "cask/quarantine"

module Cask
  module Artifact
    # Superclass for all artifacts that are installed by moving them to the target location.
    #
    # @api private
    class Moved < Relocated
      sig { returns(String) }
      def self.english_description
        "#{english_name}s"
      end

      def install_phase(**options)
        move(**options)
      end

      def uninstall_phase(**options)
        move_back(**options)
      end

      def summarize_installed
        if target.exist?
          "#{printable_target} (#{target.abv})"
        else
          Formatter.error(printable_target, label: "Missing #{self.class.english_name}")
        end
      end

      private

      def move(adopt: false, force: false, verbose: false, predecessor: nil, reinstall: false,
               command: nil, **options)
        unless source.exist?
          raise CaskError, "It seems the #{self.class.english_name} source '#{source}' is not there."
        end

        if Utils.path_occupied?(target)
          if target.directory? && target.children.empty? && matching_artifact?(predecessor)
            # An upgrade removed the directory contents but left the directory itself (see below).
            unless source.directory?
              if target.parent.writable? && !force
                target.rmdir
              else
                Utils.gain_permissions_remove(target, command: command)
              end
            end
          else
            if adopt
              ohai "Adopting existing #{self.class.english_name} at '#{target}'"
              same = command.run(
                "/usr/bin/diff",
                args:         ["--recursive", "--brief", source, target],
                verbose:      verbose,
                print_stdout: verbose,
              ).success?

              unless same
                raise CaskError,
                      "It seems the existing #{self.class.english_name} is different from " \
                      "the one being installed."
              end

              # Remove the source as we don't need to move it to the target location
              source.rmtree

              return post_move(command)
            end

            message = "It seems there is already #{self.class.english_article} " \
                      "#{self.class.english_name} at '#{target}'"
            raise CaskError, "#{message}." unless force

            opoo "#{message}; overwriting."
            delete(target, force: force, command: command, **options)
          end
        end

        ohai "Moving #{self.class.english_name} '#{source.basename}' to '#{target}'"

        Utils.gain_permissions_mkpath(target.dirname, command: command) unless target.dirname.exist?

        if target.directory? && Quarantine.app_management_permissions_granted?(app: target, command: command)
          if target.writable?
            source.children.each { |child| FileUtils.move(child, target/child.basename) }
          else
            command.run!("/bin/cp", args: ["-pR", *source.children, target],
                                    sudo: true)
          end
          Quarantine.copy_xattrs(source, target, command: command)
          source.rmtree
        elsif target.dirname.writable?
          FileUtils.move(source, target)
        else
          # default sudo user isn't necessarily able to write to Homebrew's locations
          # e.g. with runas_default set in the sudoers (5) file.
          command.run!("/bin/cp", args: ["-pR", source, target], sudo: true)
          source.rmtree
        end

        post_move(command)
      end

      # Performs any actions necessary after the source has been moved to the target location.
      def post_move(command)
        FileUtils.ln_sf target, source

        add_altname_metadata(target, source.basename, command: command)
      end

      def matching_artifact?(cask)
        return false unless cask

        cask.artifacts.any? do |a|
          a.instance_of?(self.class) && instance_of?(a.class) && a.target == target
        end
      end

      def move_back(skip: false, force: false, command: nil, **options)
        FileUtils.rm source if source.symlink? && source.dirname.join(source.readlink) == target

        if Utils.path_occupied?(source)
          message = "It seems there is already #{self.class.english_article} " \
                    "#{self.class.english_name} at '#{source}'"
          raise CaskError, "#{message}." unless force

          opoo "#{message}; overwriting."
          delete(source, force: force, command: command, **options)
        end

        unless target.exist?
          return if skip || force

          raise CaskError, "It seems the #{self.class.english_name} source '#{target}' is not there."
        end

        ohai "Backing #{self.class.english_name} '#{target.basename}' up to '#{source}'"
        source.dirname.mkpath

        # We need to preserve extended attributes between copies.
        command.run!("/bin/cp", args: ["-pR", target, source], sudo: !source.parent.writable?)

        delete(target, force: force, command: command, **options)
      end

      def delete(target, force: false, successor: nil, command: nil, **_)
        ohai "Removing #{self.class.english_name} '#{target}'"
        raise CaskError, "Cannot remove undeletable #{self.class.english_name}." if MacOS.undeletable?(target)

        return unless Utils.path_occupied?(target)

        if target.directory? && matching_artifact?(successor) && Quarantine.app_management_permissions_granted?(
          app: target, command: command,
        )
          # If an app folder is deleted, macOS considers the app uninstalled and removes some data.
          # Remove only the contents to handle this case.
          target.children.each do |child|
            if target.writable? && !force
              child.rmtree
            else
              Utils.gain_permissions_remove(child, command: command)
            end
          end
        elsif target.parent.writable? && !force
          target.rmtree
        else
          Utils.gain_permissions_remove(target, command: command)
        end
      end
    end
  end
end
