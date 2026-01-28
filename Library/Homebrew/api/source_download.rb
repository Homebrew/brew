# typed: strict
# frozen_string_literal: true

require "downloadable"

module Homebrew
  module API
    class SourceDownloadStrategy < CurlDownloadStrategy
      sig { override.returns(Pathname) }
      def symlink_location
        cache/name
      end
    end

    class SourceDownload
      include Downloadable

      sig {
        params(
          url:      String,
          checksum: T.nilable(Checksum),
          mirrors:  T::Array[String],
          cache:    T.nilable(Pathname),
        ).void
      }
      def initialize(url, checksum, mirrors: [], cache: nil)
        super()
        @url = T.let(URL.new(url, using: API::SourceDownloadStrategy), URL)
        @checksum = checksum
        @mirrors = mirrors
        @cache = cache
      end

      sig { override.returns(API::SourceDownloadStrategy) }
      def downloader
        T.cast(super, API::SourceDownloadStrategy)
      end

      sig { override.returns(String) }
      def download_queue_type = "API Source"

      sig { override.returns(Pathname) }
      def cache
        @cache || super
      end

      sig { returns(Pathname) }
      def symlink_location
        downloader.symlink_location
      end
    end
  end
end
