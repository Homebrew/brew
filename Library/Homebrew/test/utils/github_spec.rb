# typed: true
# frozen_string_literal: true

require "utils/github"

RSpec.describe GitHub do
  describe "::sponsorship_tiers" do
    it "returns published tiers with one-time prices spread over twelve months" do
      allow(GitHub::API).to receive(:open_graphql).with(
        a_string_including("tiers(first: 100, includeUnpublished: false)", "description",
                           "monthlyPriceInDollars", "isOneTime"),
        variables: { user: "Homebrew" }, scopes: ["user"],
      ).and_return("organization" => {
        "sponsorsListing" => {
          "tiers" => {
            "nodes" => [
              { "description" => "Logo in our README", "monthlyPriceInDollars" => 1500, "isOneTime" => false },
              { "description" => "Logo for twelve months", "monthlyPriceInDollars" => 12_000, "isOneTime" => true },
              nil,
            ],
          },
        },
      })

      expect(described_class.sponsorship_tiers("Homebrew"))
        .to eq([{ description: "Logo in our README", monthly_amount: 1500 },
                { description: "Logo for twelve months", monthly_amount: 1000 }])
    end
  end

  describe "::sponsorships" do
    test_each([nil, 0, 1750].product(%w[User Organization], [false, true])) do |monthly_amount, type, one_time|
      it "handles $#{monthly_amount.inspect} #{type} sponsorships with one-time payments #{one_time}" do
        allow(GitHub::API).to receive(:paginate_graphql).with(
          a_string_including("monthlyPriceInDollars", "description", "__typename",
                             "isOneTimePayment", "tierSelectedAt"),
          variables: { user: "Homebrew" }, scopes: ["user"], raise_errors: false,
        ).and_yield("data" => {
          "organization" => {
            "sponsorshipsAsMaintainer" => {
              "nodes"    => [{
                "isOneTimePayment" => one_time,
                "tierSelectedAt"   => "2026-10-01T00:00:00Z",
                "sponsorEntity"    => { "__typename" => type, "login" => "sponsor", "name" => nil },
                "tier"             => monthly_amount && {
                  "monthlyPriceInDollars" => monthly_amount,
                  "description"           => "Name and logo in our README",
                },
              }],
              "pageInfo" => { "hasNextPage" => false },
            },
          },
        })

        expect(described_class.sponsorships("Homebrew")).to eq(one_time ? [] : [{
          type:,
          login:            "sponsor",
          name:             "sponsor",
          monthly_amount:   monthly_amount || 0,
          tier_description: (monthly_amount && "Name and logo in our README").to_s,
          started_at:       "2026-10-01T00:00:00Z",
        }])
      end
    end
  end

  describe "::members_by_team" do
    it "reports an inaccessible team without assuming the token scope is missing" do
      allow(GitHub::API).to receive(:open_graphql).and_return({
        "organization" => {
          "teams" => { "nodes" => [] },
          "team"  => nil,
        },
      })

      expect { described_class.members_by_team("Homebrew", "maintainers") }
        .to raise_error(
          GitHub::API::Error,
          "Could not access the team Homebrew/maintainers. Please check that your GitHub account has access to the " \
          "team and that your token has the required permissions.",
        )
    end
  end

  describe "::API.commit" do
    it "fetches the main branch commit by default" do
      commit = { "sha" => "abc123" }

      expect(GitHub::API).to receive(:open_rest).with(
        "https://api.github.com/repos/Homebrew/brew/commits/main",
        request_method: :GET,
      ).and_return(commit)

      expect(GitHub::API.commit("Homebrew", "brew")).to eq(commit)
    end

    it "fetches a commit for a branch ref with path separators" do
      commit = { "sha" => "def456" }

      expect(GitHub::API).to receive(:open_rest).with(
        "https://api.github.com/repos/Homebrew/brew/commits/feature%2Ffoo",
        request_method: :GET,
      ).and_return(commit)

      expect(GitHub::API.commit("Homebrew", "brew", branch: "feature/foo")).to eq(commit)
    end
  end

  describe "::search_query_string" do
    it "builds a query with the given hash parameters formatted as key:value" do
      query = described_class.search_query_string(user: "Homebrew", repo: "brew")
      expect(query).to eq("q=user%3AHomebrew+repo%3Abrew&per_page=100")
    end

    it "adds a variable number of top-level string parameters to the query when provided" do
      query = described_class.search_query_string("value1", "value2", user: "Homebrew")
      expect(query).to eq("q=value1+value2+user%3AHomebrew&per_page=100")
    end

    it "turns array values into multiple key:value parameters" do
      query = described_class.search_query_string(user: ["Homebrew", "caskroom"])
      expect(query).to eq("q=user%3AHomebrew+user%3Acaskroom&per_page=100")
    end
  end

  describe "::search_issues" do
    it "queries GitHub issues with the passed parameters" do
      issue = { "title" => "Shall we move more things to taps?" }

      expect(GitHub::API).to receive(:open_rest) do |uri|
        expect(uri.to_s).to eq("https://api.github.com/search/issues?" \
                               "q=brew+search+repo%3AHomebrew%2Flegacy-homebrew+" \
                               "author%3AMikeMcQuaid+type%3Aissue+no%3Amilestone&per_page=100")
        { "items" => [issue] }
      end

      expect(described_class.search_issues("brew search",
                                           repo:   "Homebrew/legacy-homebrew",
                                           author: "MikeMcQuaid",
                                           type:   "issue",
                                           no:     "milestone")).to eq([issue])
    end
  end

  describe "::create_issue_comment" do
    it "posts a GitHub issue comment" do
      response = { "html_url" => "https://github.com/Homebrew/homebrew-core/issues/123#issuecomment-1" }

      expect(GitHub::API).to receive(:open_rest).with(
        "https://api.github.com/repos/Homebrew/homebrew-core/issues/123/comments",
        data:   { body: "Comment body" },
        scopes: GitHub::CREATE_ISSUE_FORK_OR_PR_SCOPES,
      ).and_return(response)

      expect(described_class.create_issue_comment("Homebrew/homebrew-core", 123, "Comment body")).to eq(response)
    end
  end

  describe "::repository_approved_reviews", :needs_network do
    it "can get reviews for a pull request" do
      reviews = described_class.repository_approved_reviews("Homebrew", "homebrew-core", 1, commit: "deadbeef")
      expect(reviews).to eq([])
    end
  end

  describe "::get_workflow_run" do
    it "matches uppercase expected pull request head SHAs" do
      allow(GitHub::API).to receive_messages(open_rest: { "id" => 1 }, open_graphql: {
        "repository" => {
          "pullRequest" => {
            "commits" => {
              "nodes" => [
                {
                  "commit" => {
                    "oid"         => "abcdef",
                    "checkSuites" => { "nodes" => [] },
                  },
                },
              ],
            },
          },
        },
      })

      expect(described_class.get_workflow_run("Homebrew", "homebrew-core", "1", head_sha: "ABCDEF").first).to eq([])
    end

    it "fails when the pull request head has changed" do
      allow(GitHub::API).to receive_messages(open_rest: { "id" => 1 }, open_graphql: {
        "repository" => {
          "pullRequest" => {
            "commits" => {
              "nodes" => [
                {
                  "commit" => {
                    "oid"         => "actual",
                    "checkSuites" => { "nodes" => [] },
                  },
                },
              ],
            },
          },
        },
      })

      expect do
        described_class.get_workflow_run("Homebrew", "homebrew-core", "1", head_sha: "expected")
      end.to raise_error(GitHub::API::Error, /Pull request #1 is at actual but expected expected/)
    end
  end

  describe "::get_artifact_urls" do
    it "fails to find a nonexistent workflow", :needs_network do
      expect do
        described_class.get_artifact_urls(
          described_class.get_workflow_run("Homebrew", "homebrew-core", "1"),
        )
      end.to raise_error(/No matching check suite found/)
    end

    it "fails to find artifacts that don't exist", :needs_network do
      expect do
        described_class.get_artifact_urls(
          described_class.get_workflow_run("Homebrew", "homebrew-core", "252626",
                                           workflow_id: "triage.yml", artifact_pattern: "false_artifact"),
        )
      end.to raise_error(/No artifacts with the pattern .+ were found/)
    end

    it "gets artifact URLs" do
      allow(GitHub::API).to receive(:paginate_rest).with(
        "https://api.github.com/repos/Homebrew/homebrew-core/actions/runs/19058874927/artifacts",
        per_page: 50, scopes: GitHub::CREATE_ISSUE_FORK_OR_PR_SCOPES,
      ).and_yield("artifacts" => [{
        "name"                 => "event_payload",
        "created_at"           => "2025-11-04T12:00:00Z",
        "archive_download_url" => "https://api.github.com/repos/Homebrew/homebrew-core/actions/artifacts/4457761305/zip",
      }])

      expect(described_class.get_artifact_urls(
               [[{
                 "status"      => "COMPLETED",
                 "workflowRun" => {
                   "databaseId" => 19_058_874_927,
                   "url"        => "https://github.com/Homebrew/homebrew-core/actions/runs/19058874927",
                 },
               }], "Homebrew", "homebrew-core", "252626", "triage.yml",
                GitHub::CREATE_ISSUE_FORK_OR_PR_SCOPES, "event_payload"],
             )).to eq(["https://api.github.com/repos/Homebrew/homebrew-core/actions/artifacts/4457761305/zip"])
    end
  end

  describe "::pull_request_commits", :needs_network do
    let(:hashes) do
      %w[
        188606a4a9587365d930b02c98ad6857b1d00150
        25a71fe1ea1558415d6496d23834dc70778ddee5
      ]
    end

    it "gets commit hashes for a pull request" do
      expect(described_class.pull_request_commits("Homebrew", "legacy-homebrew", 50678)).to eq(hashes)
    end

    it "gets commit hashes for a paginated pull request API response" do
      expect(described_class.pull_request_commits("Homebrew", "legacy-homebrew", 50678, per_page: 1)).to eq(hashes)
    end
  end
end
