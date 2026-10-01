# typed: true
# frozen_string_literal: true

require "open3"
require_relative "../../../.github/scripts/approve_stale_lead_maintainer_prs"

RSpec.describe StaleLeadMaintainerPrApproval do
  subject(:approval) { described_class.new }

  let(:now) { Time.utc(2026, 9, 8, 12) }
  let(:api_url) { "https://api.github.com/repos/Homebrew/brew" }
  let(:report_query) { "state=open&head=Homebrew%3Aapprove-stale-lead-maintainer-prs&per_page=1" }
  let(:event_name) { "schedule" }
  let(:pr_number) { "" }
  let(:approvals) { [] }
  let(:pull_request) do
    {
      "number"     => 1,
      "title"      => "Update a command",
      "user"       => { "login" => "lead-maintainer" },
      "created_at" => (now - (48 * 60 * 60)).iso8601,
      "draft"      => false,
      "head"       => { "sha" => "head-sha", "repo" => { "full_name" => "Homebrew/brew", "fork" => false } },
    }
  end
  let(:reviews) do
    [{ "user"         => { "login" => "copilot-pull-request-reviewer[bot]", "type" => "Bot" },
       "state"        => "COMMENTED",
       "submitted_at" => (now - 3600).iso8601,
       "commit_id"    => "head-sha" }]
  end
  let(:other_reviews) do
    [{ "user"         => { "login" => "lead-maintainer", "type" => "User" },
       "state"        => "APPROVED",
       "submitted_at" => (now - (7 * 24 * 60 * 60)).iso8601 }]
  end
  let(:search_pages) { { 1 => [{ "number" => 2 }] } }
  let(:files) { [{ "filename" => "Library/Homebrew/cmd/example.rb" }] }
  let(:check_runs) { [{ "name" => "tests", "status" => "completed", "conclusion" => "success" }] }
  let(:statuses) { [] }
  let(:responses) do
    {
      "#{api_url}/pulls?per_page=100&state=open"             => [[pull_request]],
      "#{api_url}/pulls/1"                                   => pull_request,
      "#{api_url}/pulls?#{report_query}"                     => [pull_request],
      "#{api_url}/pulls/1/reviews?per_page=100&"             => [reviews],
      "#{api_url}/pulls/2/reviews?per_page=100&"             => [other_reviews],
      "#{api_url}/pulls/1/files?per_page=100&"               => [files],
      "#{api_url}/commits/head-sha/check-runs?per_page=100&" => [{ "check_runs" => check_runs }],
      "#{api_url}/commits/head-sha/status"                   => { "statuses" => statuses },
    }
  end

  around do |example|
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) do
        File.write("README.md", "Homebrew's [Lead Maintainers] include [a maintainer](https://github.com/lead-maintainer).\n")
        File.write("gh", <<~SH)
          #!/bin/sh
          printf '%s\\n' "$@" > "$GH_TEST_ARGS"
          cat > "$GH_TEST_INPUT"
          if [ -n "${GH_TEST_RESPONSES:-}" ]; then
            exec "#{RbConfig.ruby}" -rjson -e \
              'puts JSON.generate(JSON.parse(File.read(ARGV[0], encoding: Encoding::UTF_8)).fetch(ARGV[1]))' \
              "$GH_TEST_RESPONSES" "$2"
          fi
          printf '%s' "$GH_TEST_RESPONSE"
          printf '%s' "$GH_TEST_ERROR" >&2
          exit "${GH_TEST_EXIT:-0}"
        SH
        File.chmod(0755, "gh")
        ENV["PATH"] = "#{directory}:#{ENV.fetch("PATH")}"
        ENV["GH_TEST_ARGS"] = File.join(directory, "args")
        ENV["GH_TEST_INPUT"] = File.join(directory, "input")
        ENV["GH_TEST_RESPONSE"] = "[[]]"
        ENV["GH_TEST_ERROR"] = ""
        ENV["GH_TEST_EXIT"] = "0"
        ENV.delete("GH_TEST_RESPONSES")
        example.run
      end
    end
  end

  before do
    ENV["GITHUB_REPOSITORY"] = "Homebrew/brew"
    ENV["GITHUB_SERVER_URL"] = "https://github.com"
    ENV["GITHUB_EVENT_NAME"] = event_name
    ENV["PR_NUMBER"] = pr_number
    ENV.delete("GITHUB_STEP_SUMMARY")
    ENV.delete("GITHUB_REF_NAME")
    allow(Time).to receive(:now).and_return(now)
    allow(approval).to receive(:puts)
    allow(approval).to receive(:gh_api) do |url, *flags, data: {}|
      if flags == ["--method", "POST"]
        approvals << [url, data]
        "{}"
      elsif url.start_with?("https://api.github.com/search/issues?")
        page = URI.decode_www_form(URI.parse(url).query.to_s).to_h.fetch("page")
        JSON.generate("items" => search_pages.fetch(Integer(page)))
      else
        JSON.generate(responses.fetch(url))
      end
    end
  end

  it "loads independently of Homebrew without running approvals" do
    stdout, stderr, status = Open3.capture3(
      { "RUBYOPT" => nil, "RUBYLIB" => nil, "GITHUB_REPOSITORY" => nil },
      RbConfig.ruby, "-I", "#{Gem.loaded_specs.fetch("sorbet-runtime").full_gem_path}/lib",
      "-e", "require ARGV.fetch(0); puts defined?(Homebrew).inspect",
      File.expand_path("../../../.github/scripts/approve_stale_lead_maintainer_prs.rb", __dir__)
    )

    expect([status.success?, stdout, stderr]).to eq([true, "nil\n", ""])
  end

  it "runs as a standalone Ruby script when there are no open PRs" do
    stdout, stderr, status = Open3.capture3(
      { "RUBYOPT" => nil, "RUBYLIB" => nil },
      RbConfig.ruby, "-I", "#{Gem.loaded_specs.fetch("sorbet-runtime").full_gem_path}/lib",
      File.expand_path("../../../.github/scripts/approve_stale_lead_maintainer_prs.rb", __dir__)
    )

    expect([status.success?, stdout, stderr])
      .to eq([true, "Evaluating 0 pull request(s).\nApproving 0 pull request(s).\n", ""])
  end

  it "approves an eligible PR at the age and recent-approval boundaries" do
    approval.run

    expect(approvals).to contain_exactly(
      ["#{api_url}/pulls/1/reviews", hash_including(event: "APPROVE", body: include("PR [#2]"))],
    )
  end

  it "runs the complete approval path under standalone Ruby" do
    query = URI.encode_www_form(
      q:        "repo:Homebrew/brew is:pr reviewed-by:lead-maintainer review:approved updated:>=2026-09-01",
      per_page: 100,
      page:     1,
    )
    responses["https://api.github.com/search/issues?#{query}"] = { "items" => search_pages.fetch(1) }
    responses["#{api_url}/pulls/1/reviews"] = {}
    File.write("responses.json", JSON.generate(responses))
    ENV["GH_TEST_RESPONSES"] = File.expand_path("responses.json")
    File.write("clock.rb", "def Time.now = Time.at(#{now.to_i}).utc\n")
    stdout, stderr, status = Open3.capture3(
      { "RUBYOPT" => nil, "RUBYLIB" => nil },
      RbConfig.ruby, "-I", "#{Gem.loaded_specs.fetch("sorbet-runtime").full_gem_path}/lib",
      "-r", "./clock.rb", File.expand_path("../../../.github/scripts/approve_stale_lead_maintainer_prs.rb", __dir__)
    )

    expect([status.success?, stdout, stderr, JSON.parse(File.read(ENV.fetch("GH_TEST_INPUT")))])
      .to match([true, include("Approved pull request #1."), "", hash_including("event" => "APPROVE")])
  end

  it "parses non-ASCII API responses without a UTF-8 locale" do
    pull_request["title"] = "Update a command \u{1F37A}"
    query = URI.encode_www_form(
      q:        "repo:Homebrew/brew is:pr reviewed-by:lead-maintainer review:approved updated:>=2026-09-01",
      per_page: 100,
      page:     1,
    )
    responses["https://api.github.com/search/issues?#{query}"] = { "items" => search_pages.fetch(1) }
    responses["#{api_url}/pulls/1/reviews"] = {}
    File.write("responses.json", JSON.generate(responses))
    File.write("clock.rb", "def Time.now = Time.at(#{now.to_i}).utc\n")
    stdout, stderr, status = Open3.capture3(
      { "RUBYOPT" => nil, "RUBYLIB" => nil, "LC_ALL" => "C", "LANG" => "C",
        "GH_TEST_RESPONSES" => File.expand_path("responses.json") },
      RbConfig.ruby, "-I", "#{Gem.loaded_specs.fetch("sorbet-runtime").full_gem_path}/lib",
      "-r", "./clock.rb", File.expand_path("../../../.github/scripts/approve_stale_lead_maintainer_prs.rb", __dir__)
    )

    expect([status.success?, stdout, stderr]).to match([true, include("\u{1F37A}"), ""])
  end

  it "reports a non-ASCII API error without a UTF-8 locale" do
    stdout, stderr, status = Open3.capture3(
      { "RUBYOPT" => nil, "RUBYLIB" => nil, "LC_ALL" => "C", "LANG" => "C",
        "GH_TEST_ERROR" => "gh: not found \u{1F37A}", "GH_TEST_EXIT" => "1" },
      RbConfig.ruby, "-I", "#{Gem.loaded_specs.fetch("sorbet-runtime").full_gem_path}/lib",
      File.expand_path("../../../.github/scripts/approve_stale_lead_maintainer_prs.rb", __dir__)
    )

    expect([status.success?, stdout, stderr])
      .to match([false, "", include("GitHub API request failed: gh: not found \u{1F37A}")])
  end

  it "rejects a draft" do
    pull_request["draft"] = true
    approval.run

    expect(approvals).to be_empty
  end

  it "rejects a fork" do
    pull_request["head"]["repo"]["fork"] = true
    approval.run

    expect(approvals).to be_empty
  end

  it "rejects a different head repository" do
    pull_request["head"]["repo"]["full_name"] = "someone/brew"
    approval.run

    expect(approvals).to be_empty
  end

  it "rejects an author who is not a lead maintainer" do
    pull_request["user"]["login"] = "contributor"
    approval.run

    expect(approvals).to be_empty
  end

  it "rejects a PR younger than 48 hours" do
    pull_request["created_at"] = (now - (48 * 60 * 60) + 1).iso8601
    approval.run

    expect(approvals).to be_empty
  end

  it "rejects a recent approval older than seven days" do
    other_reviews.first["submitted_at"] = (now - (7 * 24 * 60 * 60) - 1).iso8601
    approval.run

    expect(approvals).to be_empty
  end

  it "does not count an approval of the candidate PR itself" do
    search_pages[1] = [{ "number" => 1 }]
    approval.run

    expect(approvals).to be_empty
  end

  it "checks later search pages for a qualifying approval" do
    search_pages[1] = Array.new(100) { { "number" => 1 } }
    search_pages[2] = [{ "number" => 2 }]
    approval.run

    expect(approvals.length).to eq(1)
  end

  it "rejects a PR with a human review" do
    reviews << reviews.first.merge("user" => { "login" => "reviewer", "type" => "User" })
    approval.run

    expect(approvals).to be_empty
  end

  it "requires a Copilot bot review" do
    reviews.clear
    approval.run

    expect(approvals).to be_empty
  end

  it "does not approve the same commit twice" do
    reviews << reviews.first.merge("user"  => { "login" => "github-actions[bot]", "type" => "Bot" },
                                   "state" => "APPROVED")
    approval.run

    expect(approvals).to be_empty
  end

  it "can approve a new commit after an earlier bot approval" do
    reviews << reviews.first.merge("user" => { "login" => "github-actions[bot]", "type" => "Bot" },
                                   "state" => "APPROVED", "commit_id" => "old-head")
    approval.run

    expect(approvals.length).to eq(1)
  end

  it "rejects a change to its own script" do
    files << { "filename" => ".github/scripts/approve_stale_lead_maintainer_prs.rb" }
    approval.run

    expect(approvals).to be_empty
  end

  it "rejects a change to the lead maintainer list" do
    files << { "filename" => "README.md" }
    approval.run

    expect(approvals).to be_empty
  end

  it "preserves the existing exclusion for the GitHub helper" do
    files << { "filename" => "Library/Homebrew/utils/github.rb" }
    approval.run

    expect(approvals).to be_empty
  end

  it "rejects a failing non-required check" do
    check_runs << { "name" => "optional", "status" => "completed", "conclusion" => "failure" }
    approval.run

    expect(approvals).to be_empty
  end

  it "rejects an unfinished check" do
    check_runs.first["status"] = "in_progress"
    check_runs.first["conclusion"] = nil
    approval.run

    expect(approvals).to be_empty
  end

  it "requires at least one check run" do
    check_runs.clear
    approval.run

    expect(approvals).to be_empty
  end

  it "accepts neutral and skipped checks" do
    check_runs.push(
      { "name" => "neutral", "status" => "completed", "conclusion" => "neutral" },
      { "name" => "skipped", "status" => "completed", "conclusion" => "skipped" },
    )
    approval.run

    expect(approvals.length).to eq(1)
  end

  it "rejects a failing commit status" do
    statuses << { "context" => "external CI", "state" => "failure" }
    approval.run

    expect(approvals).to be_empty
  end

  context "when triggered by a push" do
    let(:event_name) { "push" }

    it "reports eligibility without approving" do
      approval.run

      expect(approvals).to be_empty
    end
  end

  context "when triggered manually" do
    let(:event_name) { "workflow_dispatch" }
    let(:pr_number) { "1" }

    it "fails a request for an ineligible PR" do
      pull_request["draft"] = true

      status = begin
        approval.run
      rescue SystemExit => e
        e.status
      end

      expect(status).to eq(1)
    end

    it "approves an eligible requested PR" do
      approval.run

      expect(approvals.length).to eq(1)
    end
  end

  it "writes the approval result to the step summary" do
    ENV["GITHUB_STEP_SUMMARY"] = "summary.md"
    approval.run

    expect(File.read("summary.md")).to include("- Approved by this run: true")
  end

  context "when running on a weekend" do
    let(:now) { Time.utc(2026, 9, 12, 12) }

    it "does not approve" do
      approval.run

      expect(approvals).to be_empty
    end
  end

  describe "GitHub API requests" do
    before do
      described_class.class_eval { public :rest, :paginated_rest }
      allow(approval).to receive(:gh_api).and_call_original
    end

    it "combines array pages returned by gh" do
      ENV["GH_TEST_RESPONSE"] = '[[{"number":1}],[{"number":2}]]'

      expect(approval.paginated_rest("#{api_url}/pulls")).to eq([{ "number" => 1 }, { "number" => 2 }])
    end

    it "preserves object pages for check runs" do
      ENV["GH_TEST_RESPONSE"] = '[{"check_runs":[{"name":"first"}]},{"check_runs":[{"name":"second"}]}]'

      expect(approval.paginated_rest("#{api_url}/commits/head-sha/check-runs"))
        .to eq([{ "check_runs" => [{ "name" => "first" }] }, { "check_runs" => [{ "name" => "second" }] }])
    end

    it "requests all pages with the existing query parameters" do
      approval.paginated_rest("#{api_url}/pulls", "state=open")

      expect(File.readlines(ENV.fetch("GH_TEST_ARGS"), chomp: true))
        .to eq(["api", "#{api_url}/pulls?per_page=100&state=open", "--paginate", "--slurp"])
    end

    it "sends approval bodies as JSON on stdin" do
      ENV["GH_TEST_RESPONSE"] = "{}"
      body = "Approval with quotes, a newline\nand literal $(text) and `text`."
      approval.rest("#{api_url}/pulls/1/reviews", data: { event: "APPROVE", body: }, request_method: :POST)

      expect([File.readlines(ENV.fetch("GH_TEST_ARGS"), chomp: true),
              JSON.parse(File.read(ENV.fetch("GH_TEST_INPUT")))])
        .to eq([["api", "#{api_url}/pulls/1/reviews", "--method", "POST", "--input", "-"],
                { "event" => "APPROVE", "body" => body }])
    end

    it "stops on an API failure even if stdout contains valid JSON" do
      ENV["GH_TEST_EXIT"] = "1"
      ENV["GH_TEST_ERROR"] = "permission denied"

      expect { approval.run }.to raise_error(RuntimeError, "GitHub API request failed: permission denied")
    end

    it "stops on invalid JSON" do
      ENV["GH_TEST_RESPONSE"] = "invalid"

      expect { approval.run }.to raise_error(JSON::ParserError)
    end
  end
end
