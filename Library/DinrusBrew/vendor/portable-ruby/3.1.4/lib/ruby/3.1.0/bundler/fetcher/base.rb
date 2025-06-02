# frozen_string_literal: true

module Bundler
  class Fetcher
    class Base
      attr_reader :downloader
      attr_reader :display_uri
      attr_reader :remote

      def initialize(downloader, remote, display_uri)
        raise "Abstract class" if self.class == Base
        @downloader = downloader
        @remote = remote
        @display_uri = display_uri
      end

      def remote_uri
        @remote.uri
      end

      def fetch_uri
        @fetch_uri ||= if remote_uri.host == "rubygems.org"
          uri = remote_uri.dup
          uri.host = "index.rubygems.org"
          uri
        else
          remote_uri
        end
      end

      def available?
        true
      end

      def api_fetcher?
        false
      end

      private

      def log_specs(debug_msg)
        if Bundler.ui.debug?
          Bundler.ui.debug debug_msg
        else
          Bundler.ui.info ".", false
        end
      end
    end
  end
end
