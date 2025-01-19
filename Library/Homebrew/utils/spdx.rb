# typed: strict
# frozen_string_literal: true

require "utils/curl"
require "utils/github"

# Helper module for updating SPDX license data.
module SPDX
  module_function

  DATA_PATH = T.let((HOMEBREW_DATA_PATH/"spdx").freeze, Pathname)
  API_URL = "https://api.github.com/repos/spdx/license-list-data/releases/latest"
  LICENSEREF_PREFIX = "LicenseRef-Homebrew-"
  ALLOWED_LICENSE_SYMBOLS = [
    :public_domain,
    :cannot_represent,
  ].freeze

  sig { returns(T::Hash[String, T.untyped]) }
  def license_data
    @license_data ||= T.let(JSON.parse((DATA_PATH/"spdx_licenses.json").read), T.nilable(T::Hash[String, T.untyped]))
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def exception_data
    @exception_data ||= T.let(JSON.parse((DATA_PATH/"spdx_exceptions.json").read),
                              T.nilable(T::Hash[String, T.untyped]))
  end

  sig { returns(String) }
  def latest_tag
    @latest_tag ||= T.let(GitHub::API.open_rest(API_URL)["tag_name"], T.nilable(String))
  end

  sig { params(to: Pathname).void }
  def download_latest_license_data!(to: DATA_PATH)
    data_url = "https://raw.githubusercontent.com/spdx/license-list-data/#{latest_tag}/json/"
    Utils::Curl.curl_download("#{data_url}licenses.json", to: to/"spdx_licenses.json")
    Utils::Curl.curl_download("#{data_url}exceptions.json", to: to/"spdx_exceptions.json")
  end

  sig {
    params(
      license_expression: T.any(
        String,
        Symbol,
        T::Hash[T.any(Symbol, String), T.untyped],
        T::Array[String],
      ),
    ).returns(
      [
        T::Array[T.any(String, Symbol)], T::Array[String]
      ],
    )
  }
  def parse_license_expression(license_expression)
    licenses = T.let([], T::Array[T.any(String, Symbol)])
    exceptions = T.let([], T::Array[String])

    case license_expression
    when String, Symbol
      licenses.push license_expression
    when Hash, Array
      if license_expression.is_a? Hash
        license_expression = license_expression.filter_map do |key, value|
          if key.is_a? String
            licenses.push key
            exceptions.push value[:with]
            next
          end
          value
        end
      end

      license_expression.each do |license|
        sub_license, sub_exception = parse_license_expression license
        licenses += sub_license
        exceptions += sub_exception
      end
    end

    [licenses, exceptions]
  end

  sig { params(license: T.any(String, Symbol)).returns(T::Boolean) }
  def valid_license?(license)
    return ALLOWED_LICENSE_SYMBOLS.include? license if license.is_a? Symbol

    license = license.delete_suffix "+"
    license_data["licenses"].any? { |spdx_license| spdx_license["licenseId"] == license }
  end

  sig { params(license: T.any(String, Symbol)).returns(T::Boolean) }
  def deprecated_license?(license)
    return false if ALLOWED_LICENSE_SYMBOLS.include? license
    return false unless valid_license?(license)

    license = license.to_s.delete_suffix "+"
    license_data["licenses"].none? do |spdx_license|
      spdx_license["licenseId"] == license && !spdx_license["isDeprecatedLicenseId"]
    end
  end

  sig { params(exception: String).returns(T::Boolean) }
  def valid_license_exception?(exception)
    exception_data["exceptions"].any? do |spdx_exception|
      spdx_exception["licenseExceptionId"] == exception && !spdx_exception["isDeprecatedLicenseId"]
    end
  end

  sig {
    params(
      license_expression: T.any(String, Symbol, T::Hash[T.nilable(T.any(Symbol, String)), T.untyped]),
      bracket:            T::Boolean,
      hash_type:          T.nilable(T.any(String, Symbol)),
    ).returns(T.nilable(String))
  }
  def license_expression_to_string(license_expression, bracket: false, hash_type: nil)
    case license_expression
    when String
      license_expression
    when Symbol
      LICENSEREF_PREFIX + license_expression.to_s.tr("_", "-")
    when Hash
      expressions = []

      if license_expression.keys.length == 1
        hash_type = license_expression.keys.first
        if hash_type.is_a? String
          expressions.push "#{hash_type} WITH #{license_expression[hash_type][:with]}"
        else
          expressions += license_expression[hash_type].map do |license|
            license_expression_to_string license, bracket: true, hash_type:
          end
        end
      else
        bracket = false
        license_expression.each do |expression|
          expressions.push license_expression_to_string([expression].to_h, bracket: true)
        end
      end

      operator = if hash_type == :any_of
        " OR "
      else
        " AND "
      end

      if bracket
        "(#{expressions.join operator})"
      else
        expressions.join operator
      end
    end
  end

  sig {
    params(
      string: T.nilable(String),
    ).returns(
      T.nilable(
        T.any(
          String,
          Symbol,
          T::Hash[T.any(String, Symbol), T.untyped],
        ),
      ),
    )
  }
  def string_to_license_expression(string)
    return if string.blank?

    result = string
    result_type = nil

    and_parts = string.split(/ and (?![^(]*\))/i)
    if and_parts.length > 1
      result = and_parts
      result_type = :all_of
    else
      or_parts = string.split(/ or (?![^(]*\))/i)
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
      with_parts = string.split(/ with /i, 2)
      if with_parts.length > 1
        { with_parts.first => { with: with_parts.second } }
      else
        return result unless result.start_with?(LICENSEREF_PREFIX)

        license_sym = result.delete_prefix(LICENSEREF_PREFIX).downcase.tr("-", "_").to_sym
        ALLOWED_LICENSE_SYMBOLS.include?(license_sym) ? license_sym : result
      end
    end
  end

  sig {
    params(
      license: T.any(String, Symbol),
    ).returns(
      T.any(
        [T.any(String, Symbol)],
        [String, T.nilable(String), T::Boolean],
      ),
    )
  }
  def license_version_info(license)
    return [license] if ALLOWED_LICENSE_SYMBOLS.include? license

    match = license.match(/-(?<version>[0-9.]+)(?:-.*?)??(?<or_later>\+|-only|-or-later)?$/)
    return [license] if match.blank?

    license_name = license.to_s.split(match[0].to_s).first
    or_later = match["or_later"].present? && %w[+ -or-later].include?(match["or_later"])

    # [name, version, later versions allowed?]
    # e.g. GPL-2.0-or-later --> ["GPL", "2.0", true]
    [license_name, match["version"], or_later]
  end

  sig {
    params(license_expression: T.any(String, Symbol, T::Hash[Symbol, T.untyped]),
           forbidden_licenses: T::Hash[Symbol, T.untyped]).returns(T::Boolean)
  }
  def licenses_forbid_installation?(license_expression, forbidden_licenses)
    case license_expression
    when String, Symbol
      forbidden_licenses_include? license_expression.to_s, forbidden_licenses
    when Hash
      key = license_expression.keys.first
      return false if key.nil?

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

  sig {
    params(
      license:            T.any(Symbol, String),
      forbidden_licenses: T::Hash[T.any(Symbol, String), T.untyped],
    ).returns(T::Boolean)
  }
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
