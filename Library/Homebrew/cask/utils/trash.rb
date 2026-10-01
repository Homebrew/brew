# typed: strict
# frozen_string_literal: true

require "cask/utils"
require "fileutils"
require "system_command"
require "uri"

module Cask
  module Utils
    module Trash
      extend SystemCommand::Mixin

      sig {
        params(paths: Pathname, command: T.nilable(T.class_of(SystemCommand)))
          .returns([T::Array[String], T::Array[String]])
      }
      def self.trash(*paths, command: nil)
        freedesktop_trash(*paths)
      end

      sig { params(paths: Pathname).returns([T::Array[String], T::Array[String]]) }
      def self.freedesktop_trash(*paths)
        return [[], []] if paths.empty?

        files_path = home_trash_path/"files"
        info_path = home_trash_path/"info"

        files_path.mkpath
        info_path.mkpath

        trashed, untrashable = paths.partition do |path|
          trash_path(path, files_path:, info_path:)
          true
        rescue
          false
        end

        [trashed.map(&:to_s), untrashable.map(&:to_s)]
      end

      sig { returns(Pathname) }
      def self.home_trash_path
        Pathname.new(ENV["XDG_DATA_HOME"].presence || "#{Dir.home}/.local/share")/"Trash"
      end
      private_class_method :home_trash_path

      sig { params(path: Pathname, files_path: Pathname, info_path: Pathname).void }
      def self.trash_path(path, files_path:, info_path:)
        basename = path.basename.to_s
        deletion_date = Time.now.strftime("%Y-%m-%dT%H:%M:%S")
        suffix = 0

        Kernel.loop do
          candidate = suffix.zero? ? basename : "#{basename}.#{suffix}"
          target_path = files_path/candidate
          target_info_path = info_path/"#{candidate}.trashinfo"

          if target_path.exist? || target_path.symlink?
            suffix += 1
            next
          end

          begin
            File.open(target_info_path, File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
              file.write <<~EOS
                [Trash Info]
                Path=#{URI::DEFAULT_PARSER.escape(path.to_s)}
                DeletionDate=#{deletion_date}
              EOS
            end
          rescue Errno::EEXIST
            suffix += 1
            next
          end

          begin
            FileUtils.mv(path, target_path)
          rescue
            target_info_path.delete if target_info_path.exist?
            Kernel.raise
          end

          return
        end
      end
      private_class_method :trash_path
    end
  end
end

require "extend/os/cask/utils/trash"
