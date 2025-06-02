# frozen_string_literal: true

module Bundler
  class CompactIndexClient
    class Updater
      class MismatchedChecksumError < Error
        def initialize(path, message)
          super "The checksum of /#{path} does not match the checksum provided by the server! Something is wrong. #{message}"
        end
      end

      def initialize(fetcher)
        @fetcher = fetcher
      end

      def update(remote_path, local_path, etag_path)
        append(remote_path, local_path, etag_path) || replace(remote_path, local_path, etag_path)
      rescue CacheFile::DigestMismatchError => e
        raise MismatchedChecksumError.new(remote_path, e.message)
      rescue Zlib::GzipFile::Error
        raise Bundler::HTTPError
      end

      private

      def append(remote_path, local_path, etag_path)
        return false unless local_path.file? && local_path.size.nonzero?

        CacheFile.copy(local_path) do |file|
          etag = etag_path.read.tap(&:chomp!) if etag_path.file?
          etag ||= generate_etag(etag_path, file) # Remove this after 2.5.0 has been out for a while.

          # Subtract a byte to ensure the range won't be empty.
          # Avoids 416 (Range Not Satisfiable) responses.
          response = @fetcher.call(remote_path, request_headers(etag, file.size - 1))
          break true if response.is_a?(Gem::Net::HTTPNotModified)

          file.digests = parse_digests(response)
          # server may ignore Range and return the full response
          if response.is_a?(Gem::Net::HTTPPartialContent)
            break false unless file.append(response.body.byteslice(1..-1))
          else
            file.write(response.body)
          end
          CacheFile.write(etag_path, etag_from_response(response))
          true
        end
      end

      # request without range header to get the full file or a 304 Not Modified
      def replace(remote_path, local_path, etag_path)
        etag = etag_path.read.tap(&:chomp!) if etag_path.file?
        response = @fetcher.call(remote_path, request_headers(etag))
        return true if response.is_a?(Gem::Net::HTTPNotModified)
        CacheFile.write(local_path, response.body, parse_digests(response))
        CacheFile.write(etag_path, etag_from_response(response))
      end

      def request_headers(etag, range_start = nil)
        headers = {}
        headers["Range"] = "bytes=#{range_start}-" if range_start
        headers["If-None-Match"] = %("#{etag}") if etag
        headers
      end

      def etag_for_request(etag_path)
        etag_path.read.tap(&:chomp!) if etag_path.file?
      end

      # When first releasing this opaque etag feature, we want to generate the old MD5 etag
      # based on the content of the file. After that it will always use the saved opaque etag.
      # This transparently saves existing users with good caches from updating a bunch of files.
      # Remove this behavior after 2.5.0 has been out for a while.
      def generate_etag(etag_path, file)
        etag = file.md5.hexdigest
        CacheFile.write(etag_path, etag)
        etag
      end

      def etag_from_response(response)
        return unless response["ETag"]
        etag = response["ETag"].delete_prefix("W/")
        return if etag.delete_prefix!('"') && !etag.delete_suffix!('"')
        etag
      end

      # Unwraps and returns a Hash of digest algorithms and base64 values
      # according to RFC 8941 Structured Field Values for HTTP.
      # https://www.rfc-editor.org/rfc/rfc8941#name-parsing-a-byte-sequence
      # Ignores unsupported algorithms.
      def parse_digests(response)
        return unless header = response["Repr-Digest"] || response["Digest"]
        digests = {}
        header.split(",") do |param|
          algorithm, value = param.split("=", 2)
          algorithm.strip!
          algorithm.downcase!
          next unless SUPPORTED_DIGESTS.key?(algorithm)
          next unless value = byte_sequence(value)
          digests[algorithm] = value
        end
        digests.empty? ? nil : digests
      end

      # Unwrap surrounding colons (byte sequence)
      # The wrapping characters must be matched or we return nil.
      # Also handles quotes because right now rubygems.org sends them.
      def byte_sequence(value)
        return if value.delete_prefix!(":") && !value.delete_suffix!(":")
        return if value.delete_prefix!('"') && !value.delete_suffix!('"')
        value
      end
    end
  end
end
