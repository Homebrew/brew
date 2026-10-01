# typed: strict
# frozen_string_literal: true

require "utils/output"

require "json"
require "tempfile"
require "utils/curl"

module Homebrew
  module Vulns
    # Base class for read-only loaders of a single upstream JSON feed cached
    # under `HOMEBREW_CACHE/vulns/`. Subclasses implement {.data_url},
    # {.cache_filename} and `#initialize(data)` (which validates the parsed
    # payload) and may override {.default_max_age}. {.load} handles freshness,
    # atomic refresh and stale-cache fallback uniformly.
    class CachedFeed
      extend T::Helpers
      extend Utils::Output::Mixin

      abstract!

      class Error < RuntimeError; end

      sig { abstract.returns(String) }
      def self.data_url; end

      sig { abstract.returns(String) }
      def self.cache_filename; end

      sig { overridable.returns(Integer) }
      def self.default_max_age = 86_400

      sig { overridable.params(data: T.anything).void }
      def initialize(data); end

      sig { params(cache: Pathname, max_age: Integer).returns(T.attached_class) }
      def self.load(cache: HOMEBREW_CACHE/"vulns", max_age: default_max_age)
        cache_file = cache/cache_filename
        return from_file(cache_file) if cache_file.exist? && (Time.now - cache_file.mtime) <= max_age

        refresh(cache_file)
      rescue ErrorDuringExecution, Error => e
        raise unless cache_file.exist?

        opoo "Failed to refresh #{cache_filename} (#{e.message.lines.first&.strip}); " \
             "using cached copy from #{cache_file.mtime}."
        from_file(cache_file)
      end

      # Download to a per-process sibling temp file and validate before
      # atomically replacing the cache so a failed, truncated or concurrent
      # fetch cannot corrupt the stale copy.
      sig { params(cache_file: Pathname).returns(T.attached_class) }
      def self.refresh(cache_file)
        cache_file.dirname.mkpath
        Tempfile.create([cache_filename, ".download"], cache_file.dirname.to_s) do |tmp|
          tmp.close
          path = Pathname(tmp.path)
          Utils::Curl.curl_download("--fail", "--silent", "--compressed", data_url, to: path)
          loaded = from_file(path)
          File.rename(path, cache_file)
          return loaded
        end
      end

      sig { params(path: Pathname).returns(T.attached_class) }
      def self.from_file(path)
        new(JSON.parse(path.read))
      rescue JSON::ParserError => e
        raise Error, "Failed to parse #{cache_filename} at #{path}: #{e.message}"
      end

      sig { params(value: T.anything).returns(T.nilable(T::Hash[String, T.untyped])) }
      def as_hash(value)
        case value
        when Hash then value
        end
      end
    end
  end
end
