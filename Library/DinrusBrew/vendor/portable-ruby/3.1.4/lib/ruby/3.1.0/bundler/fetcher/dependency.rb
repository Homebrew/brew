# frozen_string_literal: true

require_relative "base"
require "cgi"

module Bundler
  class Fetcher
    class Dependency < Base
      def available?
        @available ||= fetch_uri.scheme != "file" && downloader.fetch(dependency_api_uri)
      rescue NetworkDownError => e
        raise HTTPError, e.message
      rescue AuthenticationRequiredError
        # Fail since we got a 401 from the server.
        raise
      rescue HTTPError
        false
      end

      def api_fetcher?
        true
      end

      def specs(gem_names, full_dependency_list = [], last_spec_list = [])
        query_list = gem_names.uniq - full_dependency_list

        log_specs "Query List: #{query_list.inspect}"

        return last_spec_list if query_list.empty?

        spec_list, deps_list = Bundler::Retry.new("dependency api", FAIL_ERRORS).attempts do
          dependency_specs(query_list)
        end

        returned_gems = spec_list.map(&:first).uniq
        specs(deps_list, full_dependency_list + returned_gems, spec_list + last_spec_list)
      rescue MarshalError
        Bundler.ui.info "" unless Bundler.ui.debug? # new line now that the dots are over
        Bundler.ui.debug "could not fetch from the dependency API, trying the full index"
        nil
      rescue HTTPError, GemspecError
        Bundler.ui.info "" unless Bundler.ui.debug? # new line now that the dots are over
        Bundler.ui.debug "could not fetch from the dependency API\nit's suggested to retry using the full index via `bundle install --full-index`"
        nil
      end

      def dependency_specs(gem_names)
        Bundler.ui.debug "Query Gemcutter Dependency Endpoint API: #{gem_names.join(",")}"

        gem_list = unmarshalled_dep_gems(gem_names)
        get_formatted_specs_and_deps(gem_list)
      end

      def unmarshalled_dep_gems(gem_names)
        gem_list = []
        gem_names.each_slice(Source::Rubygems::API_REQUEST_SIZE) do |names|
          marshalled_deps = downloader.fetch(dependency_api_uri(names)).body
          gem_list.concat(Bundler.load_marshal(marshalled_deps))
        end
        gem_list
      end

      def get_formatted_specs_and_deps(gem_list)
        deps_list = []
        spec_list = []

        gem_list.each do |s|
          deps_list.concat(s[:dependencies].map(&:first))
          deps = s[:dependencies].map {|n, d| [n, d.split(", ")] }
          spec_list.push([s[:name], s[:number], s[:platform], deps])
        end
        [spec_list, deps_list]
      end

      def dependency_api_uri(gem_names = [])
        uri = fetch_uri + "api/v1/dependencies"
        uri.query = "gems=#{CGI.escape(gem_names.sort.join(","))}" if gem_names.any?
        uri
      end
    end
  end
end
