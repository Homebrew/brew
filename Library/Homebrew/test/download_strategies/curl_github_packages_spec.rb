# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe CurlGitHubPackagesDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version, **specs) }

  let(:name) { "foo" }
  let(:url) { "https://#{GitHubPackages::URL_DOMAIN}/v2/homebrew/core/spec_test/manifests/1.2.3" }
  let(:version) { "1.2.3" }
  let(:specs) { { headers: ["Accept: application/vnd.oci.image.index.v1+json"] } }
  let(:authorization) { nil }
  let(:checksum) { "d7b9f4e8bf83608b71fe958a99f19f2e5e68bb2582965d32e41759c24f1aef97" }
  let(:head_response) do
    <<~HTTP
      HTTP/2 200\r
      content-length: 12671\r
      content-type: application/vnd.oci.image.index.v1+json\r
      docker-content-digest: sha256:7d752ee92d9120e3884b452dce15328536a60d468023ea8e9f4b09839a5442e5\r
      docker-distribution-api-version: registry/2.0\r
      etag: "sha256:7d752ee92d9120e3884b452dce15328536a60d468023ea8e9f4b09839a5442e5"\r
      date: Sun, 02 Apr 2023 22:45:08 GMT\r
      x-github-request-id: 8814:FA5A:14DAFB5:158D7A2:642A0574\r
    HTTP
  end

  describe "#fetch" do
    before do
      stub_const("HOMEBREW_GITHUB_PACKAGES_AUTH", authorization) if authorization.present?

      allow(strategy).to receive(:curl_version).and_return(Version.new("8.7.1"))

      allow(strategy).to receive(:system_command)
        .with(
          /curl/,
          hash_including(args: array_including("--head")),
        )
        .twice
        .and_return(instance_double(
                      SystemCommand::Result,
                      success?:    true,
                      exit_status: instance_double(Process::Status, exitstatus: 0),
                      stdout:      head_response,
                    ))

      strategy.temporary_path.dirname.mkpath
      FileUtils.touch strategy.temporary_path
    end

    it "calls curl with anonymous authentication headers" do
      expect(strategy).to receive(:system_command)
        .with(
          /curl/,
          hash_including(args: array_including_cons("--header", "Authorization: Bearer QQ==")),
        )
        .at_least(:once)
        .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

      strategy.fetch
    end

    context "with GitHub Packages authentication defined" do
      let(:authorization) { "Bearer dead-beef-cafe" }

      it "calls curl with the provided header value" do
        expect(strategy).to receive(:system_command)
          .with(
            /curl/,
            hash_including(args: array_including_cons("--header", "Authorization: #{authorization}")),
          )
          .at_least(:once)
          .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "", assert_success!: nil))

        strategy.fetch
      end
    end
  end

  describe "#cached_location" do
    let(:url) { "https://#{GitHubPackages::URL_DOMAIN}/v2/homebrew/core/foo/blobs/sha256:#{checksum}" }
    let(:specs) { { bottle: true } }

    it "uses the resolved basename without discovering existing cache files" do
      strategy.resolved_basename = "foo--1.2.3.arm64_ventura.bottle.tar.gz"

      expect(Pathname).not_to receive(:glob)

      expect(strategy.cached_location)
        .to eq(HOMEBREW_CACHE/"downloads/#{Digest::SHA256.hexdigest(url)}--foo--1.2.3.arm64_ventura.bottle.tar.gz")
    end

    context "with a custom cache" do
      let(:cache) { HOMEBREW_CACHE/"custom-cache" }
      let(:specs) { { bottle: true, cache: } }

      it "keeps cached downloads under HOMEBREW_CACHE downloads" do
        strategy.resolved_basename = "foo--1.2.3.arm64_ventura.bottle.tar.gz"

        expect(strategy.cached_location)
          .to eq(HOMEBREW_CACHE/"downloads/#{Digest::SHA256.hexdigest(url)}--foo--1.2.3.arm64_ventura.bottle.tar.gz")
        expect(strategy.symlink_location.dirname).to eq(cache)
      end
    end

    context "with mirrors" do
      let(:specs) { { bottle: true, mirrors: ["https://mirror.example/foo.tar.gz"] } }

      it "uses generic cache discovery" do
        strategy.resolved_basename = "foo--1.2.3.arm64_ventura.bottle.tar.gz"

        expect(strategy.immutable_bottle_blob?).to be false
      end
    end
  end
end
