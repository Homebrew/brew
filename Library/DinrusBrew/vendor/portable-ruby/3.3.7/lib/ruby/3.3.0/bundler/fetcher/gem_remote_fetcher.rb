# frozen_string_literal: true

require "rubygems/remote_fetcher"

module Bundler
  class Fetcher
    class GemRemoteFetcher < Gem::RemoteFetcher
      def request(*args)
        super do |req|
          req.delete("User-Agent") if headers["User-Agent"]
          yield req if block_given?
        end
      end
    end
  end
end
