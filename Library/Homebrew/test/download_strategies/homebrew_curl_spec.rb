# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe HomebrewCurlDownloadStrategy do
  subject(:strategy) do
    Class.new(described_class) do
      T.bind(self, T.class_of(HomebrewCurlDownloadStrategy))
      public :curl_output
    end.new("https://example.com/foo.tar.gz", "foo", "1.2.3")
  end

  it "uses Homebrew's curl for `curl_output` even when asked not to" do
    allow(Utils::Path).to receive(:formula_any_version_installed?).with("curl").and_return(true)
    expect(strategy).to receive(:curl_with_workarounds)
      .with(any_args, hash_including(use_homebrew_curl: true))
      .and_return(instance_double(SystemCommand::Result))

    strategy.curl_output("--head", "https://example.com/foo.tar.gz", use_homebrew_curl: false)
  end
end
