# typed: strict
# frozen_string_literal: true

require "utils/inreplace"
require "utils/output"

module Cask
  class Migrator
    extend ::Utils::Output::Mixin
    include ::Utils::Output::Mixin

    sig { returns(Cask) }
    attr_reader :old_cask, :new_cask

    sig { params(old_cask: Cask, new_cask: Cask).void }
    def initialize(old_cask, new_cask)
      raise CaskNotInstalledError, new_cask unless new_cask.installed?

      @old_cask = old_cask
      @new_cask = new_cask
    end

    # The old tokens of `new_cask` that are still installed in their own Caskroom directory.
    # A symlinked directory means the cask has already been migrated.
    sig { params(new_cask: Cask, dry_run: T::Boolean).returns(T::Array[String]) }
    def self.old_tokens_needing_migration(new_cask, dry_run: false)
      new_cask.old_tokens
              .map { |old_token| Caskroom.token_from_full_token(old_token) }
              .uniq
              .select do |old_token|
        next false if old_token == new_cask.token

        old_caskroom_path = Caskroom.path/old_token
        next false if old_caskroom_path.symlink? || !old_caskroom_path.directory?

        if Caskroom.cask_installed_caskfile(old_token).nil?
          old_caskroom_path.rmdir_if_possible unless dry_run
          next false
        end

        true
      end
    end

    sig { params(new_cask: Cask, dry_run: T::Boolean).void }
    def self.migrate_if_needed(new_cask, dry_run: false)
      old_tokens_needing_migration(new_cask).each do |old_token|
        new(Cask.new(old_token), new_cask).migrate(dry_run:)
      rescue => e
        onoe e
      end
    end

    sig { params(dry_run: T::Boolean).void }
    def migrate(dry_run: false)
      old_caskfile = old_cask.installed_caskfile
      return if old_caskfile.nil?

      new_caskroom_path = new_cask.caskroom_path
      if new_caskroom_path.directory? && !new_caskroom_path.symlink?
        uninstall_old_cask(old_caskfile, dry_run:)
      else
        move_old_cask(old_caskfile, dry_run:)
      end
    end

    sig { params(path: Pathname, old_token: String, new_token: String).void }
    def self.replace_caskfile_token(path, old_token, new_token)
      case path.extname
      when ".rb"
        ::Utils::Inreplace.inreplace path, /\A\s*cask\s+"#{Regexp.escape(old_token)}"/, "cask #{new_token.inspect}"
      when ".json"
        json = JSON.parse(path.read)
        json["token"] = new_token
        path.atomic_write json.to_json
      end
    end

    private

    # The new cask is already installed under its own token, so the old cask is a
    # separate installation that needs to be uninstalled rather than moved.
    sig { params(old_caskfile: Pathname, dry_run: T::Boolean).void }
    def uninstall_old_cask(old_caskfile, dry_run:)
      old_token = old_cask.token
      new_token = new_cask.token

      old_caskroom_path = old_cask.caskroom_path
      new_caskroom_path = new_cask.caskroom_path

      # Load the old cask from its own installed caskfile so that its artifacts (rather
      # than the artifacts of the cask it was renamed to) are the ones uninstalled.
      installed_old_cask = CaskLoader.load_from_installed_caskfile(old_caskfile)
      uninstallable, shared = installed_old_cask.artifacts.partition do |artifact|
        !shared_with_new_cask?(artifact)
      end

      if dry_run
        oh1 "Would migrate cask #{Formatter.identifier(old_token)} to #{Formatter.identifier(new_token)}"

        puts "#{new_token} is already installed, so #{old_token} would be uninstalled."
        shared.each { |artifact| puts "#{artifact} would be kept as #{new_token} installs it too." }
        puts "ln -s #{new_caskroom_path.basename} #{old_caskroom_path}"
        return
      end

      oh1 "Migrating cask #{Formatter.identifier(old_token)} to #{Formatter.identifier(new_token)}"
      puts "#{new_token} is already installed, so #{old_token} will be uninstalled."
      shared.each { |artifact| puts "Keeping #{artifact} as #{new_token} installs it too." }

      require "cask/installer"

      installed_old_cask.unpin if installed_old_cask.pinned?
      Installer.new(installed_old_cask, force: true, verbose: Context.current.verbose?,
                    default_uninstall_artifacts: ArtifactSet.new(uninstallable)).uninstall

      FileUtils.rm_rf old_caskroom_path
      FileUtils.ln_s new_caskroom_path.basename, old_caskroom_path
    end

    # Artifacts the new cask installs too must be left alone: uninstalling them would
    # remove them from the new cask, which stays installed.
    sig { params(artifact: Artifact::AbstractArtifact).returns(T::Boolean) }
    def shared_with_new_cask?(artifact)
      new_cask.artifacts.any? do |new_artifact|
        if artifact.is_a?(Artifact::Relocated)
          # Compare the paths these end up at, which is all that matters on disk.
          new_artifact.is_a?(Artifact::Relocated) && new_artifact.target == artifact.target
        else
          new_artifact.instance_of?(artifact.class) && new_artifact.to_args == artifact.to_args
        end
      end
    end

    sig { params(old_caskfile: Pathname, dry_run: T::Boolean).void }
    def move_old_cask(old_caskfile, dry_run:)
      old_token = old_cask.token
      new_token = new_cask.token

      old_caskroom_path = old_cask.caskroom_path
      new_caskroom_path = new_cask.caskroom_path

      old_installed_caskfile = old_caskfile.relative_path_from(old_caskroom_path)
      new_installed_caskfile = old_installed_caskfile.dirname/old_installed_caskfile.basename.sub(
        old_token,
        new_token,
      )

      if dry_run
        oh1 "Would migrate cask #{Formatter.identifier(old_token)} to #{Formatter.identifier(new_token)}"

        puts "cp -r #{old_caskroom_path} #{new_caskroom_path}"
        puts "mv #{new_caskroom_path}/#{old_installed_caskfile} #{new_caskroom_path}/#{new_installed_caskfile}"
        puts "rm -r #{old_caskroom_path}"
        puts "ln -s #{new_caskroom_path.basename} #{old_caskroom_path}"
        if (old_pin_path = old_cask.pin_path).symlink? && (pinned_version = old_cask.pinned_version)
          new_pin_path = new_cask.pin_path
          puts "rm #{old_pin_path}"
          puts "ln -s #{(new_caskroom_path/pinned_version).relative_path_from(new_pin_path.dirname)} #{new_pin_path}"
        end
      else
        oh1 "Migrating cask #{Formatter.identifier(old_token)} to #{Formatter.identifier(new_token)}"

        begin
          FileUtils.cp_r old_caskroom_path, new_caskroom_path
          FileUtils.mv new_caskroom_path/old_installed_caskfile, new_caskroom_path/new_installed_caskfile
          self.class.replace_caskfile_token(new_caskroom_path/new_installed_caskfile, old_token, new_token)
        rescue => e
          FileUtils.rm_rf new_caskroom_path
          raise e
        end

        FileUtils.rm_r old_caskroom_path
        FileUtils.ln_s new_caskroom_path.basename, old_caskroom_path
        if old_cask.pin_path.symlink? && (pinned_version = old_cask.pinned_version)
          begin
            new_cask.pin_path.make_relative_symlink(new_caskroom_path/pinned_version)
            old_cask.unpin
          rescue => e
            opoo "Failed to migrate cask pin from #{old_token} to #{new_token}: #{e}"
          end
        end
      end
    end
  end
end
