# typed: true
# frozen_string_literal: true

require "utils/github/patch_inclusion"

RSpec.describe GitHub::PatchInclusion do
  subject(:checker) { described_class.new }

  let(:patch_sha) { "a" * 40 }
  let(:release_sha) { "b" * 40 }
  let(:patch_url) { "https://github.com/example/project/commit/#{patch_sha}.patch?full_index=1" }
  let(:source_url) { "https://github.com/example/project/archive/refs/tags/v2.0.tar.gz" }
  let(:comparison) { "https://api.github.com/repos/example/project/compare/#{patch_sha}...#{release_sha}" }

  before do
    allow(GitHub::API).to receive(:open_rest).with(
      "https://api.github.com/repos/example/project/commits/refs%2Ftags%2Fv2.0",
    ).and_return("sha" => release_sha)
    allow(GitHub::API).to receive(:open_rest).with(comparison).and_return("status" => "ahead")
  end

  it "reports inclusion evidence for identical or descendant releases" do
    expect(%w[identical ahead].map do |status|
      allow(GitHub::API).to receive(:open_rest).with(comparison).and_return("status" => status)
      described_class.new.removal_reason(patch_url, source_url:)
    end).to all(include(
                  "https://github.com/example/project/commit/#{patch_sha}",
                  "https://github.com/example/project/compare/#{patch_sha}...#{release_sha}",
                  "v2.0",
                ))
  end

  it "retains patches for negative or unknown comparison statuses" do
    expect(%w[behind diverged unknown].map do |status|
      allow(GitHub::API).to receive(:open_rest).with(comparison).and_return("status" => status)
      described_class.new.removal_reason(patch_url, source_url:)
    end).to all(be_nil)
  end

  it "resolves archive and release download tags, including encoded slashes" do
    allow(GitHub::API).to receive(:open_rest).with(
      "https://api.github.com/repos/example/project/commits/refs%2Ftags%2Frelease%2Fv2.0",
    ).and_return("sha" => release_sha)

    paths = %w[
      archive/v2.0.tar.gz
      archive/refs/tags/v2.0.zip
      releases/download/v2.0/project.tar.xz
      archive/refs/tags/release%2Fv2.0.tar.gz
    ]
    expect(paths.map do |path|
      checker.removal_reason(patch_url, source_url: "https://github.com/example/project/#{path}")
    end).to all(be_a(String))
  end

  it "uses a pinned Git revision instead of the tag" do
    allow(GitHub::API).to receive(:open_rest).with(
      "https://api.github.com/repos/example/project/commits/#{release_sha}",
    ).and_return("sha" => release_sha)

    expect(checker.removal_reason(
             patch_url, source_url: "https://github.com/example/project.git", tag: "unresolved", revision: release_sha
           )).not_to be_nil
  end

  it "retains patches for unsupported sources and other repositories" do
    urls = %w[
      https://example.com/project-2.0.tar.gz
      https://github.com/another/project/archive/v2.0.tar.gz
      https://github.com/example/project/archive/refs/heads/main.tar.gz
    ]
    expect(urls.map do |url|
      checker.removal_reason(patch_url, source_url: url)
    end).to all(be_nil)
  end

  it "retains patches without querying GitHub when the API is disabled" do
    ENV["HOMEBREW_NO_GITHUB_API"] = "1"

    expect(GitHub::API).not_to receive(:open_rest)
    expect(checker.removal_reason(patch_url, source_url:)).to be_nil
  end

  it "caches release resolution and ancestry comparisons" do
    expect(GitHub::API).to receive(:open_rest).with(
      "https://api.github.com/repos/example/project/commits/refs%2Ftags%2Fv2.0",
    ).once.and_return("sha" => release_sha)
    expect(GitHub::API).to receive(:open_rest).with(comparison).once.and_return("status" => "ahead")

    2.times { checker.removal_reason(patch_url, source_url:) }
  end

  it "warns without retrying when GitHub cannot resolve a ref" do
    expect(GitHub::API).to receive(:open_rest).once.and_raise(GitHub::API::HTTPNotFoundError, "Not Found")

    expect { 2.times { checker.removal_reason(patch_url, source_url:) } }.to output(/Retaining patch/).to_stderr
  end

  it "stops making requests after an authentication failure" do
    expect(GitHub::API).to receive(:open_rest).once do
      raise GitHub::API::AuthenticationFailedError.new(:none, "Bad credentials")
    end
    allow(checker).to receive(:opoo)
    checker.removal_reason(patch_url, source_url:)
    checker.removal_reason(patch_url, source_url: source_url.sub("v2.0", "v3.0"))
  end
end
