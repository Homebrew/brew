# frozen_string_literal: true

# Copyright 2024 The Sigstore Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative "tuf/updater"
require "tempfile"
require "uri"
require "net/http"
require "rubygems/remote_fetcher"
require_relative "version"

module Sigstore
  module TUF
    DEFAULT_TUF_URL = "https://tuf-repo-cdn.sigstore.dev"
    STAGING_TUF_URL = "https://tuf-repo-cdn.sigstage.dev"

    class TrustUpdater
      include Loggable

      Net = defined?(Gem::Net) ? Gem::Net : Net

      attr_reader :updater

      def initialize(metadata_url, offline, metadata_dir: nil, targets_dir: nil, target_base_url: nil,
                     config: UpdaterConfig.new)
        @repo_url = metadata_url

        default_metadata_dir, default_targets_dir = get_dirs(metadata_url) unless metadata_dir && targets_dir
        @metadata_dir = metadata_dir || default_metadata_dir
        @targets_dir = targets_dir || default_targets_dir

        @offline = offline

        rsrc_prefix = if @repo_url == DEFAULT_TUF_URL
                        "prod"
                      elsif @repo_url == STAGING_TUF_URL
                        "staging"
                      end

        FileUtils.mkdir_p @metadata_dir
        FileUtils.mkdir_p @targets_dir

        if rsrc_prefix
          tuf_root = File.join(@metadata_dir, "root.json")

          unless File.exist?(tuf_root)
            File.open(tuf_root, "wb") do |f|
              File.open(File.expand_path("../../data/_store/#{rsrc_prefix}/root.json", __dir__), "rb") do |r|
                logger.info { "Copying root.json from #{r.path} to #{f.path}" }
                IO.copy_stream(r, f)
              end
            end
          end

          trusted_root_target = File.join(@targets_dir, "trusted_root.json")

          unless File.exist?(trusted_root_target)
            File.open(trusted_root_target, "wb") do |f|
              File.open(File.expand_path("../../data/_store/#{rsrc_prefix}/trusted_root.json", __dir__),
                        "rb") do |r|
                logger.info { "Copying trusted_root.json from #{r.path} to #{f.path}" }
                IO.copy_stream(r, f)
              end
            end
          end
        end

        return if @offline

        @updater = Updater.new(
          metadata_dir: @metadata_dir,
          metadata_base_url: @repo_url,
          target_base_url: (target_base_url && URI.parse(target_base_url)) ||
                           URI.join("#{@repo_url.to_s.chomp("/")}/", "targets/"),
          target_dir: @targets_dir,
          fetcher: method(:fetch),
          config:
        )
      end

      def get_dirs(url)
        app_name = "sigstore-ruby"
        app_author = "sigstore"

        repo_base = URI.encode_uri_component(url)
        home = Dir.home

        data_home = ENV.fetch("XDG_DATA_HOME", File.join(home, ".local", "share"))
        cache_home = ENV.fetch("XDG_CACHE_HOME", File.join(home, ".cache"))
        tuf_data_dir = File.join(data_home, app_name, app_author, "tuf")
        tuf_cache_dir = File.join(cache_home, app_name, app_author, "tuf")

        [File.join(tuf_data_dir, repo_base), File.join(tuf_cache_dir, repo_base)]
      end

      def trusted_root_path
        unless @updater
          logger.info { "Offline mode: using cached trusted root" }
          return File.join(@targets_dir, "trusted_root.json")
        end

        root_info = @updater.get_targetinfo("trusted_root.json")
        raise Error::NoTrustedRoot, "Unsupported TUF configuration: no trusted_root.json" unless root_info

        path = @updater.find_cached_target(root_info)
        path ||= @updater.download_target(root_info)

        path
      end

      # Path to the TUF-distributed v0.2 signing config, or nil if the repository
      # does not publish one (older repositories, or offline mode where it is not
      # vendored). Signing always requires network access, so there is no cached
      # offline fallback as there is for the trusted root.
      def signing_config_path
        return unless @updater

        info = @updater.get_targetinfo("signing_config.v0.2.json")
        return unless info

        @updater.find_cached_target(info) || @updater.download_target(info)
      end

      def refresh
        raise ArgumentError, "Offline mode: cannot refresh" if @offline || !@updater

        @updater.refresh
      end

      private

      def fetch(uri)
        uri = Gem::Uri.new uri
        raise ArgumentError, "uri scheme is invalid: #{uri.scheme.inspect}" unless %w[http https].include?(uri.scheme)

        fetcher = Gem::RemoteFetcher.fetcher
        begin
          response = fetcher.request(uri, Net::HTTP::Get, nil) do |req|
            req["User-Agent"] = Sigstore::USER_AGENT
          end
          response.uri = uri
          case response
          when Net::HTTPOK
            nil
          when Net::HTTPMovedPermanently, Net::HTTPFound, Net::HTTPSeeOther,
            Net::HTTPTemporaryRedirect
            raise Error::UnsuccessfulResponse.new("should redirects be supported?", response)
          else
            raise Error::UnsuccessfulResponse.new("FetchError: #{response.code}", response)
          end
          response.body
        rescue (defined?(Gem::Timeout::Error) ? Gem::Timeout::Error : Timeout::Error),
               IOError, SocketError, SystemCallError,
               *(OpenSSL::SSL::SSLError if Gem::HAVE_OPENSSL) => e
          raise Error::RemoteConnection, e.message
        end
      end
    end
  end
end
