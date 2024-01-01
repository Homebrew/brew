# frozen_string_literal: true

require "utils/github"

describe GitHub do
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

  describe "::search_issues", :needs_network do
    it "queries GitHub issues with the passed parameters" do
      results = described_class.search_issues("brew search",
                                              repo:   "Homebrew/legacy-homebrew",
                                              author: "MikeMcQuaid",
                                              is:     "closed")
      expect(results).not_to be_empty
      expect(results.first["title"]).to eq("Shall we run `brew update` automatically?")
    end
  end

  describe "::approved_reviews", :needs_network do
    it "can get reviews for a pull request" do
      reviews = described_class.approved_reviews("Homebrew", "homebrew-core", 1, commit: "deadbeef")
      expect(reviews).to eq([])
    end
  end

  describe "::public_member_usernames", :needs_network do
    it "gets the usernames of all publicly visible members of the organisation" do
      response = described_class.public_member_usernames("Homebrew")
      expect(response).to be_a(Array)
    end
  end

  describe "::get_artifact_url", :needs_network do
    it "fails to find a nonexistent workflow" do
      expect do
        described_class.get_artifact_url(
          described_class.get_workflow_run("Homebrew", "homebrew-core", "1"),
        )
      end.to raise_error(/No matching check suite found/)
    end

    it "fails to find artifacts that don't exist" do
      expect do
        described_class.get_artifact_url(
          described_class.get_workflow_run("Homebrew", "homebrew-core", "135608",
                                           workflow_id: "triage.yml", artifact_name: "false_artifact"),
        )
      end.to raise_error(/No artifact .+ was found/)
    end

    it "gets an artifact link" do
      url = described_class.get_artifact_url(
        described_class.get_workflow_run("Homebrew", "homebrew-core", "135608",
                                         workflow_id: "triage.yml", artifact_name: "event_payload"),
      )
      expect(url).to eq("https://api.github.com/repos/Homebrew/homebrew-core/actions/artifacts/781984175/zip")
    end
  end

  describe "::pull_request_commits", :needs_network do
    hashes = %w[188606a4a9587365d930b02c98ad6857b1d00150 25a71fe1ea1558415d6496d23834dc70778ddee5]

    it "gets commit hashes for a pull request" do
      expect(described_class.pull_request_commits("Homebrew", "legacy-homebrew", 50678)).to eq(hashes)
    end

    it "gets commit hashes for a paginated pull request API response" do
      expect(described_class.pull_request_commits("Homebrew", "legacy-homebrew", 50678, per_page: 1)).to eq(hashes)
    end
  end

  describe "::count_repo_commits" do
    let(:five_shas) { %w[abcdef ghjkl mnop qrst uvwxyz] }
    let(:ten_shas) { %w[abcdef ghjkl mnop qrst uvwxyz fedcba lkjhg ponm tsrq zyxwvu] }

    it "counts commits authored by a user" do
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/cask", "user1", "author", {}, nil).and_return(five_shas)
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/cask", "user1", "committer", {}, nil).and_return([])

      expect(described_class.count_repo_commits("homebrew/cask", "user1", {})).to eq([5, 0])
    end

    it "counts commits committed by a user" do
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/core", "user1", "author", {}, nil).and_return([])
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/core", "user1", "committer", {}, nil).and_return(five_shas)

      expect(described_class.count_repo_commits("homebrew/core", "user1", {})).to eq([0, 5])
    end

    it "calculates correctly when authored > committed with different shas" do
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/cask", "user1", "author", {}, nil).and_return(ten_shas)
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/cask", "user1", "committer", {}, nil).and_return(%w[1 2 3 4 5])

      expect(described_class.count_repo_commits("homebrew/cask", "user1", {})).to eq([10, 5])
    end

    it "calculates correctly when committed > authored" do
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/cask", "user1", "author", {}, nil).and_return(five_shas)
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/cask", "user1", "committer", {}, nil).and_return(ten_shas)

      expect(described_class.count_repo_commits("homebrew/cask", "user1", {})).to eq([5, 5])
    end

    it "deduplicates commits authored and committed by the same user" do
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/core", "user1", "author", {}, nil).and_return(five_shas)
      allow(described_class).to receive(:repo_commits_for_user)
        .with("homebrew/core", "user1", "committer", {}, nil).and_return(five_shas)

      # Because user1 authored and committed the same 5 commits.
      expect(described_class.count_repo_commits("homebrew/core", "user1", {})).to eq([5, 0])
    end
  end
end
