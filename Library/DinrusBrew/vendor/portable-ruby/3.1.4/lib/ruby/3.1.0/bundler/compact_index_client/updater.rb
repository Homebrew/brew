# frozen_string_literal: true

require_relative "../vendored_fileutils"

module Bundler
  class CompactIndexClient
    class Updater
      class MisMatchedChecksumError < Error
        def initialize(path, server_checksum, local_checksum)
          @path = path
          @server_checksum = server_checksum
          @local_checksum = local_checksum
        end

        def message
          "The checksum of /#{@path} does not match the checksum provided by the server! Something is wrong " \
            "(local checksum is #{@local_checksum.inspect}, was expecting #{@server_checksum.inspect})."
        end
      end

      def initialize(fetcher)
        @fetcher = fetcher
        require_relative "../vendored_tmpdir"
      end

      def update(local_path, remote_path, retrying = nil)
        headers = {}

        Bundler::Dir.mktmpdir("bundler-compact-index-") do |local_temp_dir|
          local_temp_path = Pathname.new(local_temp_dir).join(local_path.basename)

          # first try to fetch any new bytes on the existing file
          if retrying.nil? && local_path.file?
            copy_file local_path, local_temp_path

            headers["If-None-Match"] = etag_for(local_temp_path)
            headers["Range"] =
              if local_temp_path.size.nonzero?
                # Subtract a byte to ensure the range won't be empty.
                # Avoids 416 (Range Not Satisfiable) responses.
                "bytes=#{local_temp_path.size - 1}-"
              else
                "bytes=#{local_temp_path.size}-"
              end
          end

          response = @fetcher.call(remote_path, headers)
          return nil if response.is_a?(Net::HTTPNotModified)

          content = response.body

          etag = (response["ETag"] || "").gsub(%r{\AW/}, "")
          correct_response = SharedHelpers.filesystem_access(local_temp_path) do
            if response.is_a?(Net::HTTPPartialContent) && local_temp_path.size.nonzero?
              local_temp_path.open("a") {|f| f << slice_body(content, 1..-1) }

              etag_for(local_temp_path) == etag
            else
              local_temp_path.open("wb") {|f| f << content }

              etag.length.zero? || etag_for(local_temp_path) == etag
            end
          end

          if correct_response
            SharedHelpers.filesystem_access(local_path) do
              FileUtils.mv(local_temp_path, local_path)
            end
            return nil
          end

          if retrying
            raise MisMatchedChecksumError.new(remote_path, etag, etag_for(local_temp_path))
          end

          update(local_path, remote_path, :retrying)
        end
      rescue Zlib::GzipFile::Error
        raise Bundler::HTTPError
      end

      def etag_for(path)
        sum = checksum_for_file(path)
        sum ? %("#{sum}") : nil
      end

      def slice_body(body, range)
        body.byteslice(range)
      end

      def checksum_for_file(path)
        return nil unless path.file?
        # This must use File.read instead of Digest.file().hexdigest
        # because we need to preserve \n line endings on windows when calculating
        # the checksum
        SharedHelpers.filesystem_access(path, :read) do
          SharedHelpers.digest(:MD5).hexdigest(File.read(path))
        end
      end

      private

      def copy_file(source, dest)
        SharedHelpers.filesystem_access(source, :read) do
          File.open(source, "r") do |s|
            SharedHelpers.filesystem_access(dest, :write) do
              File.open(dest, "wb", s.stat.mode) do |f|
                IO.copy_stream(s, f)
              end
            end
          end
        end
      end
    end
  end
end
