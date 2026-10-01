# typed: strict
# frozen_string_literal: true

require "erb"
require "utils/curl"
require "utils/output"

# Repology API client.
module Repology
  extend Utils::Output::Mixin

  API_BASE = "https://repology.org/api/v1"
  HOMEBREW_CORE = "homebrew"
  HOMEBREW_CASK = "homebrew_casks"

  sig { params(last_package_in_response: T.nilable(String), repository: String).returns(T::Hash[String, T.untyped]) }
  def self.query_api(last_package_in_response = "", repository:)
    cursor = last_package_in_response.present? ? "#{ERB::Util.url_encode(last_package_in_response)}/" : ""
    url = "#{API_BASE}/projects/#{cursor}?inrepo=#{repository}&outdated=1"

    result = Utils::Curl.curl_output(
      "--fail", "--silent", url,
      use_homebrew_curl: !Utils::Curl.curl_supports_tls13?
    )
    JSON.parse(result.stdout)
  rescue
    if Homebrew::EnvConfig.developer?
      $stderr.puts result&.stderr
    else
      odebug result&.stderr.to_s
    end

    raise
  end

  sig { params(name: String, repository: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.single_package_query(name, repository:)
    url = "#{API_BASE}/project/#{ERB::Util.url_encode(name)}"

    result = Utils::Curl.curl_output(
      "--fail", "--location", "--silent", url,
      use_homebrew_curl: !Utils::Curl.curl_supports_tls13?
    )
    raise "curl exit #{result.exit_status}: #{result.stderr.strip}" unless result.success?

    data = JSON.parse(result.stdout)
    { name => data }
  rescue => e
    require "utils/backtrace"
    error_output = [result&.stderr, "#{e.class}: #{e}", Utils::Backtrace.clean(e)].compact
    if Homebrew::EnvConfig.developer?
      $stderr.puts(*error_output)
    else
      odebug(*error_output)
    end

    nil
  end

  sig { params(repositories: T::Array[T::Hash[String, T.untyped]]).returns(T.any(String, Version)) }
  def self.latest_version(repositories)
    # The status is "unique" when the package is present only in Homebrew, so
    # Repology has no way of knowing if the package is up-to-date.
    is_unique = repositories.find do |repo|
      repo["status"] == "unique"
    end.present?

    return "present only in Homebrew" if is_unique

    latest_version = repositories.find do |repo|
      repo["status"] == "newest"
    end

    # Repology cannot identify "newest" versions for packages without a version
    # scheme
    return "no latest version" if latest_version.blank?

    Version.new(latest_version.fetch("version"))
  end
end
