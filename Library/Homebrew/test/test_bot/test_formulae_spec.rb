# frozen_string_literal: true

require "dev-cmd/test-bot"
require "utils/github/artifacts"

RSpec.describe Homebrew::TestBot::TestFormulae do
  subject(:test_formulae) do
    described_class.new(tap: nil, git: nil, dry_run: false, fail_fast: false, verbose: false)
  end

  describe "#download_artifacts_from_previous_run!" do
    it "does not raise KeyError when accessing downloaded_artifacts for a new SHA" do
      # Regression test: @downloaded_artifacts uses a hash with a default block, so we must use
      # [] (not .fetch) when accessing by SHA. Using .fetch(sha) would raise KeyError for new SHAs.
      new_sha = "8e624f21ac73d02a609cfec1ce620ccfee3aa97c"
      allow(GitHub).to receive(:pull_request_labels).with("owner", "repo", 1).and_return([])
      allow(GitHub::API).to receive_messages(credentials_type: :pat, open_graphql: { "repository" => {
        "object" => {
          "checkSuites" => {
            "nodes" => [
              {
                "status"      => "COMPLETED",
                "updatedAt"   => "2024-01-01T00:00:00Z",
                "workflowRun" => { "databaseId" => 1, "event" => "pull_request", "workflow" => { "name" => "CI" } },
                "checkRuns"   => { "nodes" => [{ "name" => "conclusion", "status" => "COMPLETED" }] },
              },
            ],
          },
        },
      } })
      allow(test_formulae).to receive_messages(
        previous_github_sha:  new_sha,
        github_event_payload: { "pull_request" => { "number" => 1 } },
        artifact_metadata:    [
          {
            "name"                 => "bottles",
            "archive_download_url" => "https://example.com/artifact",
            "id"                   => 1,
          },
        ],
      )
      allow(GitHub).to receive(:download_artifact)

      Dir.mktmpdir do |tmpdir|
        Dir.chdir(tmpdir) do
          with_env("GITHUB_REPOSITORY" => "owner/repo") do
            test_formulae.send(:download_artifacts_from_previous_run!, "bottles*", dry_run: false)
          end
        end
      end

      # Proves we passed the @downloaded_artifacts[sha] access for a new SHA without KeyError.
      downloaded = test_formulae.instance_variable_get(:@downloaded_artifacts)
      expect(downloaded[new_sha]).to include("bottles")
    end
  end
end
