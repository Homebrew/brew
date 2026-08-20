# typed: strict
# frozen_string_literal: true

# Strategy for downloading via an HTTP POST request using `curl`.
# Query parameters on the URL are converted into POST parameters.
# `data` hashes are form encoded and `json` hashes are JSON encoded.
#
# @api public
class CurlPostDownloadStrategy < CurlDownloadStrategy
  private

  sig {
    override.params(url: String, resolved_url: String, timeout: T.nilable(T.any(Float, Integer)))
            .returns(T.nilable(SystemCommand::Result))
  }
  def _fetch(url:, resolved_url:, timeout:)
    raise ArgumentError, "Only use `data` or `json`, not both" if meta.key?(:data) && meta.key?(:json)

    ensure_no_insecure_redirect!(url:, resolved_url:)

    args = if meta.key?(:data)
      escape_data = ->(d) { ["-d", URI.encode_www_form([d])] }
      [url, *meta[:data].flat_map(&escape_data)]
    elsif meta.key?(:json)
      [url, "--data", JSON.generate(meta[:json]),
       "--header", "Content-Type: application/json", "--header", "Accept: application/json"]
    else
      url, query = url.split("?", 2)
      query.nil? ? [url, "-X", "POST"] : [url, "-d", query]
    end

    curl_download(*args, to: temporary_path, try_partial: @try_partial, timeout:)
  end
end
