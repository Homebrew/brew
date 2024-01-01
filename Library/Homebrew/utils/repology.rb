# typed: true
# frozen_string_literal: true

require "utils/curl"

# Repology API client.
#
# @api private
module Repology
  HOMEBREW_CORE = "homebrew"
  HOMEBREW_CASK = "homebrew_casks"
  MAX_PAGINATION = 15
  private_constant :MAX_PAGINATION

  def self.query_api(last_package_in_response = "", repository:)
    last_package_in_response += "/" if last_package_in_response.present?
    url = "https://repology.org/api/v1/projects/#{last_package_in_response}?inrepo=#{repository}&outdated=1"

    output, errors, = Utils::Curl.curl_output(url.to_s, "--silent",
                                              use_homebrew_curl: !Utils::Curl.curl_supports_tls13?)
    JSON.parse(output)
  rescue
    if Homebrew::EnvConfig.developer?
      $stderr.puts errors
    else
      odebug errors
    end

    raise
  end

  def self.single_package_query(name, repository:)
    url = "https://repology.org/api/v1/project/#{name}"

    output, errors, = Utils::Curl.curl_output("--location", "--silent", url.to_s,
                                              use_homebrew_curl: !Utils::Curl.curl_supports_tls13?)

    data = JSON.parse(output)
    { name => data }
  rescue => e
    error_output = [errors, "#{e.class}: #{e}", Utils::Backtrace.clean(e)].compact
    if Homebrew::EnvConfig.developer?
      $stderr.puts(*error_output)
    else
      odebug(*error_output)
    end

    nil
  end

  def self.parse_api_response(limit = nil, last_package = "", repository:)
    package_term = case repository
    when HOMEBREW_CORE
      "formulae"
    when HOMEBREW_CASK
      "casks"
    else
      "packages"
    end

    ohai "Querying outdated #{package_term} from Repology"

    page_no = 1
    outdated_packages = {}

    while page_no <= MAX_PAGINATION
      odebug "Paginating Repology API page: #{page_no}"

      response = query_api(last_package, repository: repository)
      outdated_packages.merge!(response)
      last_package = response.keys.max

      page_no += 1
      break if (limit && outdated_packages.size >= limit) || response.size <= 1
    end

    package_term = package_term.chop if outdated_packages.size == 1
    puts "#{outdated_packages.size} outdated #{package_term} found"
    puts

    outdated_packages.sort.to_h
  end

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

    Version.new(latest_version["version"])
  end
end
