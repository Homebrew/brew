# typed: true
# frozen_string_literal: true

require "downloadable"

module Homebrew
  module API
    class DownloadStrategy < CurlDownloadStrategy
      sig { override.returns(Pathname) }
      def symlink_location
        cache/name
      end
    end

    class Download < Downloadable
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
        @url = URL.new(url, using: API::DownloadStrategy)
        @checksum = checksum
        @mirrors = mirrors
        @cache = cache
      end

      sig { override.returns(Pathname) }
      def cache
        @cache || super
      end

      sig { returns(Pathname) }
      def symlink_location
        T.cast(downloader, API::DownloadStrategy).symlink_location
      end
    end
  end
end
