# typed: strict
# frozen_string_literal: true

require "utils/curl"
require "utils/output"

# Repology API client.
module Repology
  extend Utils::Output::Mixin

  HOMEBREW_CORE = "homebrew"
  HOMEBREW_CASK = "homebrew_casks"

  sig { params(name: String, repository: String).returns(T.nilable(T::Hash[String, T.untyped])) }
  def self.single_package_query(name, repository:)
    url = "https://repology.org/api/v1/project/#{name}"

    result = Utils::Curl.curl_output(
      "--location", "--silent", url.to_s,
      use_homebrew_curl: !Utils::Curl.curl_supports_tls13?
    )

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

  sig { params(repositories: T::Array[String]).returns(T.any(String, Version)) }
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

    Version.new(T.must(latest_version["version"]))
  end
end
