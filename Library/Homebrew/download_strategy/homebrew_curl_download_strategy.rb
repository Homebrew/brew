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

  sig {
    override.params(
      args:              String,
      secrets:           T.any(String, T::Array[String]),
      print_stdout:      T.any(T::Boolean, Symbol),
      print_stderr:      T.any(T::Boolean, Symbol),
      debug:             T.nilable(T::Boolean),
      verbose:           T.nilable(T::Boolean),
      timeout:           T.nilable(T.any(Integer, Float)),
      use_homebrew_curl: T::Boolean,
      connect_timeout:   T.nilable(T.any(Integer, Float)),
      max_time:          T.nilable(T.any(Integer, Float)),
      retries:           T.nilable(Integer),
      retry_max_time:    T.nilable(T.any(Integer, Float)),
      show_error:        T.nilable(T::Boolean),
      cookies:           T.nilable(T::Hash[String, String]),
      header:            T.nilable(T.any(String, T::Array[String])),
      referer:           T.nilable(String),
      user_agent:        T.nilable(T.any(String, Symbol)),
    ).returns(SystemCommand::Result)
  }
  def curl_output(
    *args,
    secrets: [], print_stdout: false, print_stderr: false, debug: nil, verbose: nil, timeout: nil,
    use_homebrew_curl: false, connect_timeout: nil, max_time: nil, retries: Homebrew::EnvConfig.curl_retries.to_i,
    retry_max_time: nil, show_error: true, cookies: nil, header: nil, referer: nil, user_agent: nil
  )
    raise HomebrewCurlDownloadStrategyError, url unless Utils::Path.formula_any_version_installed?("curl")

    super(
      *args,
      secrets:, print_stdout:, print_stderr:, debug:, verbose:, timeout:, use_homebrew_curl: true, connect_timeout:,
      max_time:, retries:, retry_max_time:, show_error:, cookies:, header:, referer:, user_agent:
    )
  end
end
