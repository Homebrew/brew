# typed: true
# frozen_string_literal: true

require "utils/curl"
require "utils/github"

# Helper module for updating SPDX license data.
#
# @api private
module SPDX
  module_function

  DATA_PATH = (HOMEBREW_DATA_PATH/"spdx").freeze
  API_URL = "https://api.github.com/repos/spdx/license-list-data/releases/latest"
  ALLOWED_LICENSE_SYMBOLS = [
    :public_domain,
    :cannot_represent,
  ].freeze

  def license_data
    @license_data ||= JSON.parse (DATA_PATH/"spdx_licenses.json").read
  end

  def exception_data
    @exception_data ||= JSON.parse (DATA_PATH/"spdx_exceptions.json").read
  end

  def latest_tag
    @latest_tag ||= GitHub::API.open_rest(API_URL)["tag_name"]
  end

  def download_latest_license_data!(to: DATA_PATH)
    data_url = "https://raw.githubusercontent.com/spdx/license-list-data/#{latest_tag}/json/"
    Utils::Curl.curl_download("#{data_url}licenses.json", to: to/"spdx_licenses.json")
    Utils::Curl.curl_download("#{data_url}exceptions.json", to: to/"spdx_exceptions.json")
  end

  def parse_license_expression(license_expression)
    licenses = T.let([], T::Array[T.any(String, Symbol)])
    exceptions = T.let([], T::Array[String])

    case license_expression
    when String, Symbol
      licenses.push license_expression
    when Hash, Array
      if license_expression.is_a? Hash
        license_expression = license_expression.map do |key, value|
          if key.is_a? String
            licenses.push key
            exceptions.push value[:with]
            next
          end
          value
        end.compact
      end

      license_expression.each do |license|
        sub_license, sub_exception = parse_license_expression license
        licenses += sub_license
        exceptions += sub_exception
      end
    end

    [licenses, exceptions]
  end

  def valid_license?(license)
    return ALLOWED_LICENSE_SYMBOLS.include? license if license.is_a? Symbol

    license = license.delete_suffix "+"
    license_data["licenses"].any? { |spdx_license| spdx_license["licenseId"] == license }
  end

  def deprecated_license?(license)
    return false if ALLOWED_LICENSE_SYMBOLS.include? license
    return false unless valid_license?(license)

    license = license.delete_suffix "+"
    license_data["licenses"].none? do |spdx_license|
      spdx_license["licenseId"] == license && !spdx_license["isDeprecatedLicenseId"]
    end
  end

  def valid_license_exception?(exception)
    exception_data["exceptions"].any? do |spdx_exception|
      spdx_exception["licenseExceptionId"] == exception && !spdx_exception["isDeprecatedLicenseId"]
    end
  end

  def license_expression_to_string(license_expression, bracket: false, hash_type: nil)
    case license_expression
    when String
      license_expression
    when Symbol
      license_expression.to_s.tr("_", " ").gsub(/\b(?<!\w['’`()])[a-z]/, &:capitalize)
    when Hash
      expressions = []

      if license_expression.keys.length == 1
        hash_type = license_expression.keys.first
        if hash_type.is_a? String
          expressions.push "#{hash_type} with #{license_expression[hash_type][:with]}"
        else
          expressions += license_expression[hash_type].map do |license|
            license_expression_to_string license, bracket: true, hash_type: hash_type
          end
        end
      else
        bracket = false
        license_expression.each do |expression|
          expressions.push license_expression_to_string([expression].to_h, bracket: true)
        end
      end

      operator = if hash_type == :any_of
        " or "
      else
        " and "
      end

      if bracket
        "(#{expressions.join operator})"
      else
        expressions.join operator
      end
    end
  end

  def string_to_license_expression(string)
    return if string.blank?

    result = string
    result_type = nil

    and_parts = string.split(/ and (?![^(]*\))/)
    if and_parts.length > 1
      result = and_parts
      result_type = :all_of
    else
      or_parts = string.split(/ or (?![^(]*\))/)
      if or_parts.length > 1
        result = or_parts
        result_type = :any_of
      end
    end

    if result_type
      result.map! do |part|
        part = part[1..-2] if part[0] == "(" && part[-1] == ")"
        string_to_license_expression(part)
      end
      { result_type => result }
    else
      with_parts = string.split(" with ", 2)
      if with_parts.length > 1
        { with_parts.first => { with: with_parts.second } }
      else
        result
      end
    end
  end

  def license_version_info(license)
    return [license] if ALLOWED_LICENSE_SYMBOLS.include? license

    match = license.match(/-(?<version>[0-9.]+)(?:-.*?)??(?<or_later>\+|-only|-or-later)?$/)
    return [license] if match.blank?

    license_name = license.split(match[0]).first
    or_later = match["or_later"].present? && %w[+ -or-later].include?(match["or_later"])

    # [name, version, later versions allowed?]
    # e.g. GPL-2.0-or-later --> ["GPL", "2.0", true]
    [license_name, match["version"], or_later]
  end

  def licenses_forbid_installation?(license_expression, forbidden_licenses)
    case license_expression
    when String, Symbol
      forbidden_licenses_include? license_expression.to_s, forbidden_licenses
    when Hash
      key = license_expression.keys.first
      case key
      when :any_of
        license_expression[key].all? { |license| licenses_forbid_installation? license, forbidden_licenses }
      when :all_of
        license_expression[key].any? { |license| licenses_forbid_installation? license, forbidden_licenses }
      else
        forbidden_licenses_include? key, forbidden_licenses
      end
    end
  end

  def forbidden_licenses_include?(license, forbidden_licenses)
    return true if forbidden_licenses.key? license

    name, version, = license_version_info license

    forbidden_licenses.each_value do |license_info|
      forbidden_name, forbidden_version, forbidden_or_later = *license_info
      next if forbidden_name != name

      return true if forbidden_or_later && forbidden_version <= version

      return true if forbidden_version == version
    end
    false
  end
end
