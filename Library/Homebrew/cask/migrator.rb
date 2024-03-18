# typed: true
# frozen_string_literal: true

require "cask/cask_loader"
require "utils/inreplace"

module Cask
  class Migrator
    attr_reader :old_cask, :new_cask

    sig { params(old_cask: Cask, new_cask: Cask).void }
    def initialize(old_cask, new_cask)
      raise CaskNotInstalledError, new_cask unless new_cask.installed?

      @old_cask = old_cask
      @new_cask = new_cask
    end

    sig { params(new_cask: Cask, dry_run: T::Boolean).void }
    def self.migrate_if_needed(new_cask, dry_run: false)
      old_tokens = new_cask.old_tokens
      return if old_tokens.empty?

      return unless (installed_caskfile = new_cask.installed_caskfile)

      old_cask = CaskLoader.load(installed_caskfile)
      return if new_cask.token == old_cask.token

      migrator = new(old_cask, new_cask)
      migrator.migrate(dry_run:)
    end

    sig { params(dry_run: T::Boolean).void }
    def migrate(dry_run: false)
      old_token = old_cask.token
      new_token = new_cask.token

      old_caskroom_path = old_cask.caskroom_path
      new_caskroom_path = new_cask.caskroom_path

      old_installed_caskfile = old_cask.installed_caskfile.relative_path_from(old_caskroom_path)
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
  end
end
