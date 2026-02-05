# typed: true # rubocop:todo Sorbet/StrictSigil
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

      def install_phase(**options)
        link(**options)
      end

      def uninstall_phase(**options)
        unlink(**options)
      end

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

      private

      def link(force: false, adopt: false, command: nil, **_options)
        unless source.exist?
          raise CaskError,
                "It seems the #{self.class.link_type_english_name.downcase} " \
                "source '#{source}' is not there."
        end

        if target.exist?
          message = "It seems there is already #{self.class.english_article} " \
                    "#{self.class.english_name} at '#{target}'"

          if (force || adopt) && target.symlink? &&
             (target.realpath == source.realpath || target.realpath.to_s.start_with?("#{cask.caskroom_path}/"))
            opoo "#{message}; overwriting."
            Utils.gain_permissions_remove(target, command:)
          elsif (formula = conflicting_formula)
            opoo "#{message} from formula #{formula}; skipping link."
            return
          else
            raise CaskError, "#{message}."
          end
        end

        ohai "Linking #{self.class.english_name} '#{source.basename}' to '#{target}'"
        create_filesystem_link(command)
      end

      def unlink(command: nil, **)
        return unless target.symlink?

        ohai "Unlinking #{self.class.english_name} '#{target}'"

        if (formula = conflicting_formula)
          odebug "#{target} is from formula #{formula}; skipping unlink."
          return
        end

        Utils.gain_permissions_remove(target, command:)
      end

      sig { params(command: T.class_of(SystemCommand)).void }
      def create_filesystem_link(command)
        Utils.gain_permissions_mkpath(target.dirname, command:)

        command.run! "/bin/ln", args: ["--no-dereference", "--force", "--symbolic", source, target],
                                sudo: !target.dirname.writable?
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
