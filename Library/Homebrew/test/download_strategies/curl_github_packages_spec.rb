# typed: false
# frozen_string_literal: true

require "download_strategy"

RSpec.describe CurlGitHubPackagesDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version, **specs) }

  let(:name) { "foo" }
  let(:url) { "https://#{GitHubPackages::URL_DOMAIN}/v2/homebrew/core/spec_test/manifests/1.2.3" }
  let(:version) { "1.2.3" }
  let(:specs) { { headers: ["Accept: application/vnd.oci.image.index.v1+json"] } }
  let(:authorization) { nil }
  let(:artifact_domain) { nil }
  let(:bearer_prefix) { "Bearer" }
  let(:anonymous_authorization) { "#{bearer_prefix} QQ==" }
  let(:mirror_url) { url.sub("https://#{GitHubPackages::URL_DOMAIN}", artifact_domain) if artifact_domain.present? }
  let(:mirror_download_fails) { false }
  let(:stderr) { "curl: (6) Could not resolve host: mirror.example.com" }
  let(:curl_requests) { [] }
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

  def system_command_result(success: true, stdout: "", stderr: "")
    status = instance_double(Process::Status, success?: success, exitstatus: success ? 0 : 1, termsig: nil)
    output = []
    output << [:stdout, stdout] unless stdout.empty?
    output << [:stderr, stderr] unless stderr.empty?
    SystemCommand::Result.new(["curl"], output, status, secrets: [])
  end

  describe "#fetch" do
    before do
      stub_const("HOMEBREW_GITHUB_PACKAGES_AUTH", authorization) if authorization.present?
      allow(Homebrew::EnvConfig).to receive_messages(
        artifact_domain:                  artifact_domain,
        docker_registry_basic_auth_token: nil,
        docker_registry_token:            nil,
      )

      allow(strategy).to receive(:curl_version).and_return(Version.new("8.7.1"))

      allow(strategy).to receive(:system_command) do |_, options|
        args = options.fetch(:args)
        curl_requests << args

        if args.include?("--head")
          system_command_result(stdout: head_response)
        elsif mirror_download_fails && mirror_url.present? && args.include?(mirror_url)
          system_command_result(success: false, stderr: stderr)
        else
          system_command_result
        end
      end

      strategy.temporary_path.dirname.mkpath
      FileUtils.touch strategy.temporary_path
    end

    it "calls curl with anonymous authentication headers" do
      strategy.fetch

      ghcr_requests = curl_requests.select { |args| args.include?(url) }
      expect(ghcr_requests).not_to be_empty
      expect(ghcr_requests).to all(include("Authorization: #{anonymous_authorization}"))
    end

    context "with GitHub Packages authentication defined" do
      let(:authorization) { "#{bearer_prefix} dead-beef-cafe" }

      it "calls curl with the provided header value" do
        strategy.fetch

        ghcr_requests = curl_requests.select { |args| args.include?(url) }
        expect(ghcr_requests).not_to be_empty
        expect(ghcr_requests).to all(include("Authorization: #{authorization}"))
      end
    end

    context "with artifact_domain set" do
      let(:artifact_domain) { "https://mirror.example.com/oci" }

      it "does not add GitHub Packages authentication to artifact mirror requests" do
        strategy.fetch

        mirror_requests = curl_requests.select { |args| args.include?(mirror_url) }
        expect(mirror_requests).not_to be_empty
        expect(mirror_requests).to all(satisfy { |args| !args.include?("Authorization: #{anonymous_authorization}") })
      end

      context "when the artifact mirror download fails" do
        let(:mirror_download_fails) { true }

        it "restores GitHub Packages authentication for ghcr.io fallback requests" do
          strategy.fetch

          mirror_requests = curl_requests.select { |args| args.include?(mirror_url) }
          fallback_requests = curl_requests.select { |args| args.include?(url) }

          expect(mirror_requests).not_to be_empty
          expect(fallback_requests).not_to be_empty
          expect(mirror_requests).to all(satisfy { |args| !args.include?("Authorization: #{anonymous_authorization}") })
          expect(fallback_requests).to all(include("Authorization: #{anonymous_authorization}"))
        end

        context "when authorization is already present in headers" do
          let(:authorization) { "#{bearer_prefix} dead-beef-cafe" }
          let(:specs) do
            {
              headers: [
                "Accept: application/vnd.oci.image.index.v1+json",
                "Authorization: #{authorization}",
              ],
            }
          end

          it "preserves the existing authorization header across mirror and fallback requests" do
            strategy.fetch

            relevant_requests = curl_requests.select { |args| args.include?(mirror_url) || args.include?(url) }

            expect(relevant_requests).not_to be_empty
            expect(relevant_requests).to all(include("Authorization: #{authorization}"))
            expect(relevant_requests).to all(satisfy { |args| args.count("Authorization: #{authorization}") == 1 })
          end
        end
      end
    end
  end
end
