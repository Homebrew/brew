# frozen_string_literal: true

require_relative "gem_parser"

module Bundler
  class CompactIndexClient
    class Cache
      attr_reader :directory

      def initialize(directory, fetcher = nil)
        @directory = Pathname.new(directory).expand_path
        @updater = Updater.new(fetcher) if fetcher
        @mutex = Thread::Mutex.new
        @endpoints = Set.new

        @info_root = mkdir("info")
        @special_characters_info_root = mkdir("info-special-characters")
        @info_etag_root = mkdir("info-etags")
      end

      def names
        fetch("names", names_path, names_etag_path)
      end

      def versions
        fetch("versions", versions_path, versions_etag_path)
      end

      def info(name, remote_checksum = nil)
        path = info_path(name)

        if remote_checksum && remote_checksum != SharedHelpers.checksum_for_file(path, :MD5)
          fetch("info/#{name}", path, info_etag_path(name))
        else
          Bundler::CompactIndexClient.debug { "update skipped info/#{name} (#{remote_checksum ? "versions index checksum is nil" : "versions index checksum matches local"})" }
          read(path)
        end
      end

      def reset!
        @mutex.synchronize { @endpoints.clear }
      end

      private

      def names_path = directory.join("names")
      def names_etag_path = directory.join("names.etag")
      def versions_path = directory.join("versions")
      def versions_etag_path = directory.join("versions.etag")

      def info_path(name)
        name = name.to_s
        # TODO: converge this into the info_root by hashing all filenames like info_etag_path
        if /[^a-z0-9_-]/.match?(name)
          name += "-#{SharedHelpers.digest(:MD5).hexdigest(name).downcase}"
          @special_characters_info_root.join(name)
        else
          @info_root.join(name)
        end
      end

      def info_etag_path(name)
        name = name.to_s
        @info_etag_root.join("#{name}-#{SharedHelpers.digest(:MD5).hexdigest(name).downcase}")
      end

      def mkdir(name)
        directory.join(name).tap do |dir|
          SharedHelpers.filesystem_access(dir) do
            FileUtils.mkdir_p(dir)
          end
        end
      end

      def fetch(remote_path, path, etag_path)
        if already_fetched?(remote_path)
          Bundler::CompactIndexClient.debug { "already fetched #{remote_path}" }
        else
          Bundler::CompactIndexClient.debug { "fetching #{remote_path}" }
          @updater&.update(remote_path, path, etag_path)
        end

        read(path)
      end

      def already_fetched?(remote_path)
        @mutex.synchronize { !@endpoints.add?(remote_path) }
      end

      def read(path)
        return unless path.file?
        SharedHelpers.filesystem_access(path, :read, &:read)
      end
    end
  end
end
