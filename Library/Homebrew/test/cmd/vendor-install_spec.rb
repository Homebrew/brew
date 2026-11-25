# typed: strict
# frozen_string_literal: true

require "system_command"
require "cmd/vendor-install"

RSpec.describe Homebrew::Cmd::VendorInstall do
  it "uses the configured curl options when downloading portable Ruby" do
    ENV["HOMEBREW_CURL"] = "curl"
    ENV["HOMEBREW_CURL_VERSION"] = "7.55.0"
    ENV["HOMEBREW_GITHUB_PACKAGES_AUTH"] = "Basic test-token"
    ENV["HOMEBREW_CURLRC"] = "/path with spaces/\n--insecure"
    ENV["HOMEBREW_CURL_RETRIES"] = "10"
    ENV["HOMEBREW_CURL_VERBOSE"] = "1"
    ENV["HOMEBREW_NO_INSECURE_REDIRECT"] = "1"
    ENV["HOMEBREW_QUIET"] = "1"

    args = SystemCommand.run!("/bin/bash", args: [
      "-c", <<~SH
        source "#{HOMEBREW_LIBRARY_PATH}/utils.sh"
        source "#{HOMEBREW_LIBRARY_PATH}/cmd/vendor-install.sh"
        curl() { printf '%s\\0' "$@"; cat; exit; }
        CACHED_LOCATION="#{mktmpdir}/portable-ruby.tar.gz"
        VENDOR_URLs=(https://example.com/portable-ruby.tar.gz)
        fetch
      SH
    ]).stdout.split("\0")
    input = args.pop
    expect([args.first(8), args.grep(/Authorization|test-token|@-/), input])
      .to eq([["-q", "--config", "/path with spaces/\n--insecure", "--retry", "10", "--verbose",
               "--proto-redir", "=https"], ["@-"], "Authorization: Basic test-token\n"])
  end
end
