# typed: strict
# frozen_string_literal: true

require "utils/path"

# Strategy for downloading a file using Homebrew's `curl`.
#
# @api public
class HomebrewCurlDownloadStrategy < CurlDownloadStrategy
  private

  sig {
    params(resolved_url: String, to: T.any(Pathname, String), timeout: T.nilable(T.any(Float, Integer)))
      .returns(T.nilable(SystemCommand::Result))
  }
  def _curl_download(resolved_url, to, timeout)
    raise HomebrewCurlDownloadStrategyError, url unless Utils::Path.formula_any_version_installed?("curl")

    curl_download resolved_url, to:, try_partial: @try_partial, timeout:, use_homebrew_curl: true
  end

  sig { override.params(args: String, options: T.untyped).returns(SystemCommand::Result) }
  def curl_output(*args, **options)
    raise HomebrewCurlDownloadStrategyError, url unless Utils::Path.formula_any_version_installed?("curl")

    options[:use_homebrew_curl] = true
    super
  end
end
