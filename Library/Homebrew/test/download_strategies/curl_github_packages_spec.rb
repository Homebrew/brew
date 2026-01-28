# frozen_string_literal: true

require "download_strategy"

RSpec.describe CurlGitHubPackagesDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version, **specs) }

  let(:name) { "foo" }
  let(:url) { "https://#{GitHubPackages::URL_DOMAIN}/v2/homebrew/core/spec_test/manifests/1.2.3" }
  let(:version) { "1.2.3" }
  let(:specs) { { headers: ["Accept: application/vnd.oci.image.index.v1+json"] } }
  let(:authorization) { nil }
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
end
