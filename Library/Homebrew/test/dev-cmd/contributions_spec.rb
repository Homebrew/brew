# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "cleanup"
require "dev-cmd/contributions"
require "utils/github"

RSpec.describe Homebrew::DevCmd::Contributions do
  before do
    stub_const("HOMEBREW_CACHE", mktmpdir)
    allow(GitHub::API).to receive(:open_rest).and_return({})
  end

  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "contributions"

  it "matches merger identities without conflating names or email local parts" do
    command = described_class.new([])
    results = [
      ["Alice Example", "a.example@example.com"],
      ["Alex", "unknown@example.com"],
      ["Alex", "bob@example.com"],
      ["A. Example", "123+alice@users.noreply.github.com"],
      ["Unknown", "alice@unrelated.example.com"],
    ].map do |name, email|
      output = ["merge", "base tip", name, email, name, email, "Merge pull request #123 from contributor/topic"]
               .join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)
      command.parse_git_log(
        output, { "alice" => "alice", "bob" => "bob" },
        github_identities: { "alice" => ["Alice Example", "Alex", "a.example@example.com"],
                             "bob"   => ["Alex", "bob@example.com"] }
      ).select { |_, contributions| contributions.fetch(:merged_pr_merger).positive? }.keys
    end

    expect(results).to eq([["alice"], [], ["bob"], ["alice"], []])
  end

  it "does not learn maintainer merger identities from someone else's PR commits" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    output = [
      ["merge", "base tip", "Alice", "alice@example.com", "GitHub", "noreply@github.com",
       "Merge pull request #123 from bob/topic"],
      ["tip", "base", "Alice", "alice@example.com", "Alice", "alice@example.com", "Help Bob"],
    ].map { |fields| fields.join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR) }
     .join(Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR)

    expect(command.parse_git_log(output, { "alice" => "Alice", "bob" => "Bob" })
      .transform_values { |counts| counts.fetch(:merged_pr_merger) }).to eq("alice" => 1, "bob" => 0)
  end

  it "documents the governance reporting quarters" do
    help_text = described_class.parser.generate_help_text.gsub(/\s+/, " ")

    expect(help_text).to include(
      "--maintainer-report-csv=2026-2",
      "current directory",
      "brew-contributions-FROM-to-TO-USER.csv",
      "--from and --to",
      "Only Maintainers listed at the end of that period are included",
      "role recommendations use up to four full quarters of reports",
      "Completed-period GitHub searches are cached in Homebrew's cache",
      "Merge and approval checks stop once the activity thresholds are met",
      "YEAR-1 is December of the previous year through February",
      "YEAR-2 is March through May",
      "YEAR-3 is June through August",
      "YEAR-4 is September through November",
    )
  end

  it "counts only the first approver in brew and each approver in core and cask" do
    command = described_class.new([])
    allow(GitHub::API).to receive(:paginate_graphql) do |query, variables:, &block|
      expect(query).to include("mergedAt", "author { login }")
      expect(variables).to include(number: 123)
      block.call("repository" => { "pullRequest" => {
        "mergedAt" => "2026-01-20T00:00:00Z", "author" => { "login" => "author" },
        "timelineItems" => {
          "nodes"    => [
            { "id" => "review-1", "author" => { "login" => "author" }, "submittedAt" => "2025-12-01T00:00:00Z",
              "state" => "APPROVED", "authorCanPushToRepository" => true },
            { "id" => "review-2", "author" => { "login" => "carol" }, "submittedAt" => "2025-12-10T00:00:00Z",
              "state" => "APPROVED", "authorCanPushToRepository" => false },
            { "id" => "review-3", "author" => { "login" => "alice" }, "submittedAt" => "2025-12-31T23:59:59Z",
              "state" => "APPROVED", "authorCanPushToRepository" => true },
            { "id" => "review-4", "author" => { "login" => "bob" }, "submittedAt" => "2026-01-15T12:00:00Z",
              "state" => "APPROVED", "authorCanPushToRepository" => true },
            { "id" => "review-5", "author" => { "login" => "alice" }, "submittedAt" => "2026-01-16T12:00:00Z",
              "state" => "APPROVED", "authorCanPushToRepository" => true },
          ],
          "pageInfo" => { "hasNextPage" => false },
        }
      } })
    end

    results = [
      ["Homebrew/brew", "alice"], ["Homebrew/brew", "bob"],
      ["Homebrew/homebrew-core", "bob"], ["Homebrew/homebrew-cask", "bob"],
      ["Homebrew/brew", "carol"], ["Homebrew/brew", "author"]
    ].map do |repository, user|
      command.approved_pull_request?(repository, 123, user, from: "2026-01-01", to: "2026-02-01")
    end

    expect(results).to eq([true, false, true, true, false, false])
  end

  it "reuses approval queries across users and reporting periods without moving the merge date" do
    command = described_class.new([])
    calls = 0
    allow(GitHub::API).to receive(:paginate_graphql) do |*_args, &block|
      calls += 1
      block.call("repository" => { "pullRequest" => {
        "mergedAt" => "2026-01-20T00:00:00Z", "author" => { "login" => "author" },
        "timelineItems" => {
          "nodes"    => [{ "id" => "review", "author" => { "login" => "alice" },
                        "submittedAt" => "2026-01-15T12:00:00Z",
                        "state" => "APPROVED", "authorCanPushToRepository" => true }],
          "pageInfo" => { "hasNextPage" => false },
        }
      } })
    end
    results = [
      ["alice", "2025-12-01", "2026-01-01"], ["alice", "2026-01-01", "2026-02-01"],
      ["alice", "2025-12-01", "2026-03-01"], ["bob", "2026-01-01", "2026-02-01"],
      ["alice", "2026-02-01", "2026-03-01"]
    ].map do |user, from, to|
      command.approved_pull_request?("Homebrew/brew", 123, user, from:, to:)
    end

    expect([results, calls]).to eq([[false, true, true, false, false], 1])
  end

  it "excludes unmerged PRs and merges outside the reporting period" do
    results = [nil, "2025-12-31T23:59:59Z", "2026-02-01T00:00:00Z"].each_with_index.map do |merged_at, index|
      command = described_class.new([])
      allow(GitHub::API).to receive(:paginate_graphql) do |*_args, &block|
        block.call("repository" => { "pullRequest" => {
          "mergedAt" => merged_at, "author" => { "login" => "author" },
          "timelineItems" => {
            "nodes"    => [{ "id" => "review-6", "author" => { "login" => "alice" },
                            "submittedAt" => "2026-01-15T12:00:00Z",
                          "state" => "APPROVED", "authorCanPushToRepository" => true }],
            "pageInfo" => { "hasNextPage" => false },
          }
        } })
      end

      command.approved_pull_request?("Homebrew/brew", 123 + index, "alice",
                                     from: "2026-01-01", to: "2026-02-01")
    end

    expect(results).to eq([false, false, false])
  end

  it "ignores superseded approvals and reviews submitted after the merge" do
    command = described_class.new([])
    allow(GitHub::API).to receive(:paginate_graphql) do |*_args, &block|
      block.call("repository" => { "pullRequest" => {
        "mergedAt" => "2026-01-20T00:00:00Z", "author" => { "login" => "author" },
        "timelineItems" => {
          "nodes"    => [
            { "id" => "review-7", "author" => { "login" => "alice" }, "submittedAt" => "2026-01-01T00:00:00Z",
              "state" => "APPROVED", "authorCanPushToRepository" => true },
            { "id" => "review-8", "author" => { "login" => "alice" }, "submittedAt" => "2026-01-02T00:00:00Z",
              "state" => "CHANGES_REQUESTED", "authorCanPushToRepository" => true },
            { "id" => "review-9", "author" => { "login" => "bob" }, "submittedAt" => "2026-01-03T00:00:00Z",
              "state" => "APPROVED", "authorCanPushToRepository" => true },
            { "id" => "review-10", "author" => { "login" => "alice" }, "submittedAt" => "2026-01-21T00:00:00Z",
              "state" => "APPROVED", "authorCanPushToRepository" => true },
          ],
          "pageInfo" => { "hasNextPage" => false },
        }
      } })
    end

    expect(command.approved_pull_request?("Homebrew/brew", 123, "alice",
                                          from: "2026-01-01", to: "2026-02-01")).to be false
  end

  it "finds the first qualifying approval across review pages" do
    command = described_class.new([])
    allow(GitHub::API).to receive(:paginate_graphql) do |*_args, &block|
      [[], [{ "id" => "review-11", "author" => { "login" => "alice" }, "submittedAt" => "2026-01-15T12:00:00Z",
              "state" => "APPROVED", "authorCanPushToRepository" => true }]].each do |nodes|
        block.call("repository" => { "pullRequest" => {
          "mergedAt" => "2026-01-20T00:00:00Z", "author" => { "login" => "author" },
          "timelineItems" => { "nodes" => nodes, "pageInfo" => { "hasNextPage" => nodes.empty? } }
        } })
      end
    end

    expect(command.approved_pull_request?("Homebrew/brew", 123, "alice",
                                          from: "2026-01-01", to: "2026-02-01")).to be true
  end

  it "retains approvals dismissed after pushes in core and cask but not brew" do
    command = described_class.new([])
    allow(GitHub::API).to receive(:paginate_graphql) do |*_args, &block|
      block.call("repository" => { "pullRequest" => {
        "mergedAt" => "2026-01-20T00:00:00Z", "author" => { "login" => "author" },
        "timelineItems" => {
          "nodes"    => [
            { "id" => "alice-review", "author" => { "login" => "alice" },
              "submittedAt" => "2026-01-01T00:00:00Z", "state" => "DISMISSED",
              "authorCanPushToRepository" => true },
            { "createdAt" => "2026-01-02T00:00:00Z", "previousReviewState" => "APPROVED",
              "review" => { "id" => "alice-review", "author" => { "login" => "alice" },
                            "submittedAt" => "2026-01-01T00:00:00Z", "state" => "DISMISSED",
                            "authorCanPushToRepository" => true } },
            { "id" => "bob-review", "author" => { "login" => "bob" },
              "submittedAt" => "2026-01-03T00:00:00Z", "state" => "APPROVED",
              "authorCanPushToRepository" => true },
          ],
          "pageInfo" => { "hasNextPage" => false },
        }
      } })
    end

    expect(Homebrew::DevCmd::Contributions::PRIMARY_REPOS.map do |repository|
      command.approved_pull_request?(repository, 123, "alice", from: "2026-01-01", to: "2026-02-01")
    end).to eq([false, true, true])
  end

  it "counts manual issue closures without duplicating PRs, self-closures or repeated closures" do
    command = described_class.new([])
    allow(GitHub::API).to receive(:paginate_graphql) do |*_args, &block|
      block.call("repository" => { "issues" => {
        "nodes" => [
          { "createdAt" => "2025-12-01T00:00:00Z", "author" => { "login" => "bob" }, "timelineItems" => {
            "nodes" => [
              { "actor" => { "login" => "alice" }, "createdAt" => "2026-01-10T00:00:00Z" },
              { "actor" => { "login" => "alice" }, "createdAt" => "2026-01-11T00:00:00Z" },
              { "actor" => { "login" => "bob" }, "createdAt" => "2026-01-12T00:00:00Z" },
            ], "pageInfo" => { "hasNextPage" => false }
          } },
          { "createdAt" => "2026-01-01T00:00:00Z", "author" => { "login" => "carol" }, "timelineItems" => {
            "nodes" => [
              { "actor" => { "login" => "bob" }, "createdAt" => "2026-01-15T00:00:00Z",
                "closer" => { "__typename" => "PullRequest", "mergedBy" => { "login" => "alice" } } },
              { "actor" => { "login" => "bob" }, "createdAt" => "2026-01-16T00:00:00Z",
                "closer" => { "__typename"             => "Commit",
                              "associatedPullRequests" => { "nodes" => [{ "merged" => true }] } } },
              { "actor" => { "login" => "bob" }, "createdAt" => "2026-02-01T00:00:00Z" },
            ], "pageInfo" => { "hasNextPage" => false }
          } },
        ], "pageInfo" => { "hasNextPage" => false }
      } })
    end

    expect(command.closed_issue_counts("Homebrew/brew", from: "2026-01-01", to: "2026-02-01"))
      .to eq("alice" => 1)
  end

  it "stops fetching issues when creation dates reach the reporting period end" do
    command = described_class.new([])
    pagination = { "hasNextPage" => true }
    allow(GitHub::API).to receive(:paginate_graphql) do |*_args, &block|
      pagination.replace(block.call("repository" => { "issues" => {
        "nodes"    => [{ "createdAt" => "2026-02-01T00:00:00Z" }],
        "pageInfo" => { "hasNextPage" => true, "endCursor" => "more" },
      } }))
    end
    command.closed_issue_counts("Homebrew/brew", from: "2026-01-01", to: "2026-02-01")

    expect(pagination).to eq("hasNextPage" => false)
  end

  it "uses the first README mention for Maintainer tenure" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    repository_path = Pathname("/Homebrew/brew")
    git_log_format = [
      Homebrew::DevCmd::Contributions::GIT_LOG_COMMIT_HASH_FORMAT,
      Homebrew::DevCmd::Contributions::GIT_LOG_COMMITTER_DATE_SHORT_FORMAT,
    ].join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)
    allow(Utils).to receive(:safe_popen_read).and_return("")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "log", "quarter-end-ref", "--fixed-strings",
            "-SAlice", "--format=#{git_log_format}", "--", "README.md")
      .and_return("first-mention#{Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR}2020-01-02\n")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "show", "first-mention:README.md")
      .and_return("Homebrew was created by Alice.\n")
    allow(command).to receive(:system_command)
      .with(Utils::Git.git,
            args: ["-C", repository_path, "show", "first-mention^:README.md"], print_stderr: false)
      .and_return(instance_double(SystemCommand::Result, stdout: ""))

    expect(command.maintainer_since(repository_path, "quarter-end-ref", "alice", "Alice"))
      .to eq("2020-01-02")
  end

  it "reads historical Maintainer lists using current usernames" do
    command = described_class.new(["--maintainer-report-csv=2025-3"])
    repository_path = Pathname("/Homebrew/brew")
    repository_refs = { "Homebrew/brew" => [repository_path, "origin/HEAD"] }
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "rev-list", "-1", "--before=2025-09-01",
            "origin/HEAD", "--", "README.md")
      .and_return("quarter-end-ref\n")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "show", "quarter-end-ref:README.md")
      .and_return(<<~MARKDOWN)
        Homebrew's maintainers are [Branch Vincent](https://github.com/branchvincent) and [Bob](https://github.com/bob).
        Former maintainers include [Carol](https://github.com/carol).
      MARKDOWN
    allow(command).to receive(:maintainer_since).and_return("2020-01-02")

    expect(command.maintainer_report_users(repository_refs, "2025-09-01")).to eq([
      { "branchv" => "Branch Vincent", "bob" => "Bob" }, {}, { "branchv" => "2020-01-02", "bob" => "2020-01-02" }
    ])
  end

  it "filters historical Maintainers for a requested maintainer report user" do
    command = described_class.new(["--maintainer-report-csv=2025-3", "--user=ALICE"])
    repository_path = Pathname("/Homebrew/brew")
    repository_refs = { "Homebrew/brew" => [repository_path, "origin/HEAD"] }
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "rev-list", "-1", "--before=2025-09-01",
            "origin/HEAD", "--", "README.md")
      .and_return("quarter-end-ref\n")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "show", "quarter-end-ref:README.md")
      .and_return(<<~MARKDOWN)
        Homebrew's [Lead Maintainers](url) are [Alice](https://github.com/Alice).
        Homebrew's other Maintainers are [Bob](https://github.com/bob).
      MARKDOWN
    allow(command).to receive(:maintainer_since)
      .with(repository_path, "quarter-end-ref", "Alice", "Alice")
      .and_return("2020-01-02")

    expect do
      expect(command.maintainer_report_users(repository_refs, "2025-09-01")).to eq([
        { "Alice" => "Alice" }, { "alice" => true }, { "Alice" => "2020-01-02" }
      ])
    end.to output("Scanning contributions for 1 maintainer...\n").to_stderr
  end

  it "reports an unresolved maintainer report email as an identity error" do
    command = described_class.new(["--maintainer-report-csv=2025-3", "--user=alice@example.com"])
    repository_path = Pathname("/Homebrew/brew")
    repository_refs = { "Homebrew/brew" => [repository_path, "origin/HEAD"] }
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "rev-list", "-1", "--before=2025-09-01",
            "origin/HEAD", "--", "README.md")
      .and_return("quarter-end-ref\n")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "show", "quarter-end-ref:README.md")
      .and_return("Homebrew's maintainers are [Alice](https://github.com/alice).\n")
    allow(command).to receive(:github_username_for).with("alice@example.com", to: "2025-09-01")

    expect { command.maintainer_report_users(repository_refs, "2025-09-01") }
      .to raise_error(SystemExit)
      .and output(/Could not resolve GitHub usernames for: alice@example\.com/).to_stderr
  end

  it "filters maintainer reports using a username resolved from an email" do
    command = described_class.new([
      "--maintainer-report-csv=2025-3",
      "--user=39449589+alice@users.noreply.github.com",
    ])
    repository_path = Pathname("/Homebrew/brew")
    repository_refs = { "Homebrew/brew" => [repository_path, "origin/HEAD"] }
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "rev-list", "-1", "--before=2025-09-01",
            "origin/HEAD", "--", "README.md")
      .and_return("quarter-end-ref\n")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "show", "quarter-end-ref:README.md")
      .and_return("Homebrew's maintainers are [Alice](https://github.com/alice).\n")
    allow(command).to receive(:maintainer_since)
      .with(repository_path, "quarter-end-ref", "alice", "Alice")
      .and_return("2020-01-02")

    expect(command.maintainer_report_users(repository_refs, "2025-09-01")).to eq([
      { "alice" => "Alice" }, {}, { "alice" => "2020-01-02" }
    ])
  end

  it "reports only requested users not listed as quarter-end Maintainers" do
    command = described_class.new([
      "--maintainer-report-csv=2025-3",
      "--user=bob,carol,dave",
    ])
    repository_path = Pathname("/Homebrew/brew")
    repository_refs = { "Homebrew/brew" => [repository_path, "origin/HEAD"] }
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "rev-list", "-1", "--before=2025-09-01",
            "origin/HEAD", "--", "README.md")
      .and_return("quarter-end-ref\n")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "show", "quarter-end-ref:README.md")
      .and_return("Homebrew's maintainers are [Bob](https://github.com/bob).\n")

    expect { command.maintainer_report_users(repository_refs, "2025-09-01") }
      .to raise_error(SystemExit)
      .and output(<<~EOS).to_stderr
        Error: Not listed as Maintainers at the end of the reporting period: carol and dave.
      EOS
  end

  it "rejects empty maintainer report user values" do
    command = described_class.new(["--maintainer-report-csv=2025-3", "--user=alice,,bob"])

    expect(Utils::GemSetup).not_to receive(:install_bundler_gems!)
    expect { command.run }
      .to raise_error(SystemExit)
      .and output(/`--user` must not contain empty values/).to_stderr
  end

  it "reports activity criteria with and without historical reports" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    quarter_end_ref = "quarter-end-ref"
    repository_refs = Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
      [repository, [Pathname("/#{repository}"), "origin/HEAD"]]
    end
    no_contributions = { merged_pr_merger: 0, approved_pr_review: 0, closed_issue: 0 }
    alice_results = {
      "Homebrew/brew"          => {
        merged_pr_merger: 4, approved_pr_review: 1, closed_issue: 45,
        merged_pr_author: 500, merged_pr: 500, coauthor: 500
      },
      "Homebrew/homebrew-core" => no_contributions,
      "Homebrew/homebrew-cask" => no_contributions,
    }
    bob_results = {
      "Homebrew/brew"          => {
        merged_pr_merger: 25, approved_pr_review: 0, closed_issue: 0
      },
      "Homebrew/homebrew-core" => {
        merged_pr_merger: 24, approved_pr_review: 1, closed_issue: 0
      },
      "Homebrew/homebrew-cask" => no_contributions.merge(closed_issue: 451),
    }

    allow(Utils::GemSetup).to receive(:install_bundler_gems!).with(groups: ["contributions"])
    allow(command).to receive(:prepare_contribution_repositories)
      .with(Homebrew::DevCmd::Contributions::PRIMARY_REPOS, required: true)
      .and_return(repository_refs)
    allow(Utils).to receive(:safe_popen_read).and_return("")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", Pathname("/Homebrew/brew"), "rev-list", "-1", "--before=2026-03-01",
            "origin/HEAD", "--", "README.md")
      .and_return("#{quarter_end_ref}\n")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", Pathname("/Homebrew/brew"), "show", "#{quarter_end_ref}:README.md")
      .and_return(<<~MARKDOWN)
        Homebrew's [Lead Maintainers](url) are [Alice](https://github.com/alice).
        Homebrew's other Maintainers are [Bob](https://github.com/bob).
      MARKDOWN
    allow(command).to receive(:scan_contributions)
      .with("Homebrew", Homebrew::DevCmd::Contributions::PRIMARY_REPOS, repository_refs,
            { "alice" => "Alice", "bob" => "Bob" }, from: "2025-12-01", to: "2026-03-01",
            skip_reviews_if_lead_met: true, progress: true)
      .and_return({ "alice" => alice_results, "bob" => bob_results })
    allow(command).to receive(:maintainer_since)
      .with(Pathname("/Homebrew/brew"), quarter_end_ref, "alice", "Alice")
      .and_return("2024-03-01")
    allow(command).to receive(:maintainer_since)
      .with(Pathname("/Homebrew/brew"), quarter_end_ref, "bob", "Bob")
      .and_return("2022-03-01")
    allow(command).to receive(:previous_maintainer_reports).with("2025-12-01").and_return([
      { "alice" => [true, true], "bob" => [true, false] },
      { "alice" => [true, true], "bob" => [true, true] },
      { "alice" => [true, true], "bob" => [true, true] },
    ])
    csv = <<~CSV
      username,name,since,tenure days,brew merged,brew first approvals,brew issues closed,brew total,core merged,core approvals,core issues closed,core total,cask merged,cask approvals,cask issues closed,cask total,total,maintainer met,lead met,maintainer exempt,capped,role,potential new role
      bob,Bob,2022-03-01,1461,25,0,0,25,24,1,0,25,0,0,451,451,501,true,true,false,false,Maintainer,Maintainer
      alice,Alice,2024-03-01,730,4,1,45,50,0,0,0,0,0,0,0,0,50,true,false,false,false,Lead Maintainer,Lead Maintainer
    CSV
    expect(File).to receive(:write).with("brew-contributions-2025-12-01-to-2026-03-01.csv", csv)

    expect do
      command.run
    end.to output(csv).to_stdout.and output(<<~EOS).to_stderr
      Maintainer report dates: 2025-12-01-to-2026-03-01
      Scanning contributions for 2 maintainers...
    EOS

    allow(command).to receive(:previous_maintainer_reports).with("2025-12-01").and_return([])
    csv_without_history = "#{csv.lines(chomp: true).map { |line| line.rpartition(",").first }.join("\n")}\n"
    expect(File).to receive(:write).with("brew-contributions-2025-12-01-to-2026-03-01.csv", csv_without_history)

    expect do
      command.run
    end.to output(csv_without_history).to_stdout.and output(<<~EOS).to_stderr
      Maintainer report dates: 2025-12-01-to-2026-03-01
      Scanning contributions for 2 maintainers...
    EOS
  end

  it "reads contiguous full reports for the three preceding quarters" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])

    reports = Dir.chdir(mktmpdir) do
      {
        "2025-09-01-to-2025-12-01" => [25, 25],
        "2025-06-01-to-2025-09-01" => [50, 0],
        "2025-03-01-to-2025-06-01" => [0, 0],
      }.each do |dates, totals|
        Pathname("brew-contributions-#{dates}.csv")
          .write("username,brew first approvals,brew total,core total,cask total\nAlice,0,#{totals.join(",")},0\n")
      end

      command.previous_maintainer_reports("2025-12-01")
    end

    expect(reports).to eq([
      { "alice" => [true, true] },
      { "alice" => [true, false] },
      { "alice" => [false, false] },
    ])
  end

  it "assesses the 40 overall and 20 per-repository boundaries" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    reports = Dir.chdir(mktmpdir) do
      Pathname("brew-contributions-2025-12-01-to-2026-03-01.csv").write(<<~CSV)
        username,brew first approvals,brew total,core total,cask total
        below,0,19,20,0
        single,0,40,0,0
        lead,0,20,20,0
        uneven,0,21,19,0
      CSV
      command.maintainer_activity_report("2025-12-01", "2026-03-01")
    end

    expect(reports).to eq("below" => [false, false], "single" => [true, false],
                          "lead" => [true, true], "uneven" => [true, false])
  end

  it "warns when the immediately preceding report is unavailable" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])

    expect do
      expect(Dir.chdir(mktmpdir) { command.previous_maintainer_reports("2025-12-01") }).to be_empty
    end.to output(<<~EOS).to_stderr
      Warning: Could not find brew-contributions-2025-09-01-to-2025-12-01.csv; omitting the potential new role column.
    EOS
  end

  it "combines monthly counts into quarterly activity alongside quarterly reports" do
    command = described_class.new(["--maintainer-report-csv", "--from=2026-12-01", "--to=2027-01-01"])
    reports = Dir.chdir(mktmpdir) do
      [9, 10, 11].each do |month|
        from = Date.new(2026, month, 1)
        Pathname("brew-contributions-#{from}-to-#{from.next_month}.csv")
          .write("username,brew first approvals,brew total,core total,cask total,maintainer met,lead met\n" \
                 "Alice,0,10,10,0,false,false\n")
      end
      Pathname("brew-contributions-2026-06-01-to-2026-09-01.csv")
        .write("username,brew first approvals,brew total,core total,cask total\nAlice,0,50,0,0\n")
      Pathname("brew-contributions-2026-03-01-to-2026-06-01.csv")
        .write("username,brew first approvals,brew total,core total,cask total\nAlice,0,0,0,0\n")
      command.previous_maintainer_reports("2026-12-01")
    end

    expect(reports).to eq([
      { "alice" => [true, true] }, { "alice" => [true, false] }, { "alice" => [false, false] }
    ])
  end

  context "with monthly reports" do
    sig { returns(Homebrew::DevCmd::Contributions) }
    let(:command) do
      described_class.new(["--maintainer-report-csv", "--from=2026-11-01", "--to=2026-12-01"])
    end

    before do
      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      allow(command).to receive_messages(
        prepare_contribution_repositories: {},
        maintainer_report_users:           [
          { "alice" => "Alice" }, { "alice" => true }, { "alice" => "2020-01-01" }
        ],
        scan_contributions:                {
          "alice" => Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
            count = (repository == "Homebrew/homebrew-cask") ? 0 : 5
            [repository, { merged_pr_merger: count, approved_pr_review: 0, closed_issue: 0 }]
          end,
        },
      )
      allow(command).to receive(:previous_maintainer_reports)
        .with("2026-09-01").and_return([{ "alice" => [false, false] }])
    end

    it "normalises former usernames when exempting Maintainers" do
      allow(command).to receive_messages(args: described_class.new(
        ["--maintainer-report-csv", "--from=2026-11-01", "--to=2026-12-01", "--maintainer-exempt=BRANCHVINCENT"],
      ).args, maintainer_report_users: [
        { "branchv" => "Branch" }, {}, { "branchv" => "2020-01-01" }
      ], scan_contributions: {
        "branchv" => Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
          [repository, { merged_pr_merger: 0, approved_pr_review: 0, closed_issue: 0 }]
        end,
      })
      report = Dir.chdir(mktmpdir) do
        command.run
        CSV.read("brew-contributions-2026-11-01-to-2026-12-01.csv", headers: true).first
      end

      expect(report&.values_at("maintainer exempt", "potential new role"))
        .to eq(["true", "Maintainer"])
    end

    it "warns about unmatched exemptions without blocking historical or filtered reports" do
      allow(command).to receive(:args).and_return(described_class.new(
        ["--maintainer-report-csv", "--from=2026-11-01", "--to=2026-12-01", "--maintainer-exempt=andrew"],
      ).args)

      expect { Dir.chdir(mktmpdir) { command.run } }
        .to output(/Exempt usernames not listed in this maintainer report: andrew/).to_stderr
    end

    it "retains exempt Maintainers without inventing qualifying activity" do
      allow(command).to receive_messages(args: described_class.new(
        ["--maintainer-report-csv", "--from=2026-11-01", "--to=2026-12-01", "--maintainer-exempt=ALICE"],
      ).args, maintainer_report_users: [
        { "alice" => "Alice" }, {}, { "alice" => "2020-01-01" }
      ])
      report = Dir.chdir(mktmpdir) do
        command.run
        CSV.read("brew-contributions-2026-11-01-to-2026-12-01.csv", headers: true).first
      end

      expect(report&.values_at("maintainer exempt", "maintainer met", "lead met", "potential new role"))
        .to eq(["true", nil, nil, "Maintainer"])
    end

    it "writes one month of counts but assesses a complete quarter" do
      report = Dir.chdir(mktmpdir) do
        [9, 10].each do |month|
          from = Date.new(2026, month, 1)
          Pathname("brew-contributions-#{from}-to-#{from.next_month}.csv")
            .write("username,brew first approvals,brew total,core total,cask total\nAlice,0,10,10,0\n")
        end
        command.run
        CSV.read("brew-contributions-2026-11-01-to-2026-12-01.csv", headers: true).first
      end

      expect(report&.values_at("total", "maintainer met", "lead met", "potential new role"))
        .to eq(["10", "true", "true", "Lead Maintainer"])
    end

    it "omits recommendations when a month of the assessment quarter is missing" do
      report = Dir.chdir(mktmpdir) do
        command.run
        CSV.read("brew-contributions-2026-11-01-to-2026-12-01.csv", headers: true)
      end

      expect(report.headers).not_to include("potential new role")
    end

    it "uses the latest completed quarter during an incomplete quarter" do
      allow(command).to receive(:args).and_return(described_class.new(
        ["--maintainer-report-csv", "--from=2026-09-01", "--to=2026-10-01"],
      ).args)
      allow(command).to receive(:previous_maintainer_reports)
        .with("2026-06-01").and_return([{ "alice" => [false, false] }])
      report = Dir.chdir(mktmpdir) do
        Pathname("brew-contributions-2026-06-01-to-2026-09-01.csv")
          .write("username,brew first approvals,brew total,core total,cask total\nalice,0,25,25,0\n")
        command.run
        CSV.read("brew-contributions-2026-09-01-to-2026-10-01.csv", headers: true).first
      end

      expect(report&.values_at("total", "maintainer met", "lead met", "potential new role"))
        .to eq(["10", "true", "true", "Lead Maintainer"])
    end

    it "combines weekly reports without counting overlapping monthly reports twice" do
      allow(command).to receive(:args).and_return(described_class.new(
        ["--maintainer-report-csv", "--from=2026-11-24", "--to=2026-12-01"],
      ).args)
      report = Dir.chdir(mktmpdir) do
        from = Date.new(2026, 9, 1)
        while from < Date.new(2026, 11, 24)
          Pathname("brew-contributions-#{from}-to-#{from + 7}.csv")
            .write("username,brew first approvals,brew total,core total,cask total\nalice,0,1,1,0\n")
          from += 7
        end
        Pathname("brew-contributions-2026-11-01-to-2026-12-01.csv")
          .write("username,brew first approvals,brew total,core total,cask total\nalice,0,50,50,0\n")
        command.run
        CSV.read("brew-contributions-2026-11-24-to-2026-12-01.csv", headers: true).first
      end

      expect(report&.values_at("total", "maintainer met", "lead met", "potential new role"))
        .to eq(%w[10 false false None])
    end

    it "can assess monthly requirements independently of the reporting dates" do
      stub_const("Homebrew::DevCmd::Contributions::ACTIVITY_PERIOD_MONTHS", 1)
      allow(command).to receive(:previous_maintainer_reports)
        .with("2026-11-01").and_return([{ "alice" => [false, false] }])
      report = Dir.chdir(mktmpdir) do
        command.run
        CSV.read("brew-contributions-2026-11-01-to-2026-12-01.csv", headers: true).first
      end

      expect(report&.values_at("total", "maintainer met", "lead met", "potential new role"))
        .to eq(%w[10 false false None])
    end
  end

  it "applies multi-quarter activity requirements to potential roles" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    period_end = Date.new(2026, 3, 1)
    maintainer_since = Date.new(2022, 3, 1)
    previous_reports = [
      {
        "promoted" => [true, true], "not_promoted" => [true, true],
        "demoted" => [true, false], "removed" => [false, false], "incomplete" => [true, true]
      },
      { "promoted" => [true, true], "not_promoted" => [true, false], "incomplete" => [true, true] },
      { "promoted" => [true, true], "not_promoted" => [true, true] },
    ]

    expect({
      "promoted"     => ["Maintainer", [true, true]],
      "not_promoted" => ["Maintainer", [true, true]],
      "demoted"      => ["Lead Maintainer", [true, false]],
      "removed"      => ["Maintainer", [false, false]],
      "incomplete"   => ["Maintainer", [true, true]],
    }.to_h do |user, (role, activity)|
      [user.to_sym, command.potential_maintainer_role(
        user, role, maintainer_since, period_end, activity, previous_reports
      )]
    end).to eq(
      promoted:     "Lead Maintainer",
      not_promoted: "Maintainer",
      demoted:      "Maintainer",
      removed:      "None",
      incomplete:   nil,
    )
  end

  it "writes filtered maintainer reports without overwriting the full report" do
    command = described_class.new([
      "--maintainer-report-csv=2026-1",
      "--user=BOB,39449589+alice@users.noreply.github.com",
    ])
    repository_refs = Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
      [repository, [Pathname("/#{repository}"), "origin/HEAD"]]
    end
    no_contributions = {
      merged_pr_merger: 0, approved_pr_review: 0, closed_issue: 0
    }
    results = {
      "bob"   => Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
        [repository, no_contributions]
      end,
      "Alice" => Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
        [repository, no_contributions]
      end,
    }
    csv = "filtered maintainer report\n"

    allow(Utils::GemSetup).to receive(:install_bundler_gems!).with(groups: ["contributions"])
    allow(command).to receive(:prepare_contribution_repositories)
      .with(Homebrew::DevCmd::Contributions::PRIMARY_REPOS, required: true)
      .and_return(repository_refs)
    allow(command).to receive(:maintainer_report_users)
      .with(repository_refs, "2026-03-01")
      .and_return([
        { "bob" => "Bob", "Alice" => "Alice" },
        {},
        { "bob" => "2020-01-02", "Alice" => "2020-01-02" },
      ])
    allow(command).to receive(:scan_contributions)
      .with("Homebrew", Homebrew::DevCmd::Contributions::PRIMARY_REPOS, repository_refs,
            { "bob" => "Bob", "Alice" => "Alice" }, from: "2025-12-01", to: "2026-03-01",
            skip_reviews_if_lead_met: true, progress: true)
      .and_return(results)
    allow(command).to receive(:generate_maintainer_report_csv).and_return(csv)
    expect(File).to receive(:write)
      .with("brew-contributions-2025-12-01-to-2026-03-01-alice-bob.csv", csv)

    expect { command.run }
      .to output(csv).to_stdout
      .and output("Maintainer report dates: 2025-12-01-to-2026-03-01\n").to_stderr
  end

  it "uses the shared Git scanner for non-Maintainers" do
    command = described_class.new([
      "--user=alice", "--repositories=Homebrew/brew", "--from=2026-01-01", "--to=2026-02-01", "--csv"
    ])
    repository_refs = { "Homebrew/brew" => [Pathname("/Homebrew/brew"), "origin/HEAD"] }
    results = { "alice" => { "Homebrew/brew" => {
      merged_pr_author: 1, merged_pr_merger: 0, merged_pr: 1, approved_pr_review: 2, coauthor: 3
    } } }

    allow(Utils::GemSetup).to receive(:install_bundler_gems!).with(groups: ["contributions"])
    allow(command).to receive(:prepare_contribution_repositories)
      .with(["Homebrew/brew"], required: false)
      .and_return(repository_refs)
    allow(command).to receive(:scan_contributions)
      .with("Homebrew", ["Homebrew/brew"], repository_refs, { "alice" => "alice" },
            from: "2026-01-01", to: "2026-02-01", skip_reviews_if_lead_met: false, progress: false)
      .and_return(results)

    expect do
      command.run
    end.to output(<<~CSV).to_stdout.and output(/alice contributed.*6 times \(total\)/).to_stderr
      username,repo,authored,merged,PRs,reviews,coauthored,total
      alice,all,1,0,1,2,3,6
    CSV
  end

  it "marks capped merged-PR searches with no matching requested repositories as lower bounds" do
    command = described_class.new([
      "--user=alice", "--repositories=Homebrew/brew", "--from=2026-01-01", "--to=2026-02-01"
    ])
    repository_refs = { "Homebrew/brew" => [Pathname("/Homebrew/brew"), "origin/HEAD"] }
    results = { "alice" => { "Homebrew/brew" => {
      merged_pr_author: 0, merged_pr_merger: 0, merged_pr: 0, approved_pr_review: 0, coauthor: 0,
      merged_pr_author_hit_cap: 1
    } } }

    allow(command).to receive(:prepare_contribution_repositories)
      .with(["Homebrew/brew"], required: false)
      .and_return(repository_refs)
    allow(command).to receive(:scan_contributions)
      .with("Homebrew", ["Homebrew/brew"], repository_refs, { "alice" => "alice" },
            from: "2026-01-01", to: "2026-02-01", skip_reviews_if_lead_met: false, progress: false)
      .and_return(results)

    expect { command.run }.to output(/alice contributed >=0 times \(total\)/).to_stdout
  end

  it "uses merge dates for repositories without local Git history" do
    command = described_class.new(["--user=alice", "--repositories=Homebrew/untapped"])
    repository = "Homebrew/untapped"
    allow(GitHub).to receive(:search_approved_pull_requests_in_user_or_organisation).and_return([])
    expect(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2026-01-01..2026-01-31")
      .and_return([{ "number" => 123, "repository_url" => "#{GitHub::API_URL}/repos/#{repository}" }])

    results = command.scan_contributions(
      "Homebrew",
      [repository],
      {},
      { "alice" => "alice" },
      from:                     "2026-01-01",
      to:                       "2026-02-01",
      skip_reviews_if_lead_met: false,
      progress:                 false,
    )

    expect(results.fetch("alice").fetch(repository)).to eq(
      merged_pr_author: 1, merged_pr_merger: 0, merged_pr: 1, approved_pr_review: 0, coauthor: 0,
    )
  end

  it "distributes organisation-wide merged PR searches by repository" do
    command = described_class.new(["--user=alice", "--repositories=Homebrew/brew,Homebrew/homebrew-core"])
    repositories = %w[Homebrew/brew Homebrew/homebrew-core]
    allow(GitHub).to receive(:search_approved_pull_requests_in_user_or_organisation).and_return([])
    expect(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2026-01-01..2026-01-31")
      .and_return([{ "number" => 123, "repository_url" => "#{GitHub::API_URL}/repos/Homebrew/homebrew-core" }])

    results = command.scan_contributions(
      "Homebrew",
      repositories,
      {},
      { "alice" => "alice" },
      from:                     "2026-01-01",
      to:                       "2026-02-01",
      skip_reviews_if_lead_met: false,
      progress:                 false,
    )

    expect(results.fetch("alice").transform_values { |counts| counts.fetch(:merged_pr_author) }).to eq(
      "Homebrew/brew" => 0, "Homebrew/homebrew-core" => 1,
    )
  end

  it "scopes capped merged PR searches by repository until Lead activity is known" do
    command = described_class.new(["--user=alice"])
    repositories = Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
      [repository, [Pathname("/#{repository}"), "origin/HEAD"]]
    end
    no_contributions = {
      merged_pr_author: 0, merged_pr_merger: 0, merged_pr: 0, approved_pr_review: 0, coauthor: 0
    }
    allow(Utils).to receive(:safe_popen_read).and_return("brew", "core", "cask")
    allow(command).to receive(:parse_git_log) { { "alice" => no_contributions.dup } }
    expect(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2025-12-01..2026-02-28")
      .and_return(Array.new(100) do |index|
        { "number" => index, "repository_url" => "#{GitHub::API_URL}/repos/Homebrew/homebrew-cask" }
      end)
    expect(GitHub).to receive(:search_issues)
      .with("", is: "merged", repo: "Homebrew/brew", author: "alice", merged: "2025-12-01..2026-02-28")
      .and_return(Array.new(25) { |index| { "number" => index + 100 } })
    expect(GitHub).not_to receive(:search_approved_pull_requests_in_user_or_organisation)

    results = command.scan_contributions(
      "Homebrew",
      repositories.keys,
      repositories,
      { "alice" => "Alice" },
      from:                     "2025-12-01",
      to:                       "2026-03-01",
      skip_reviews_if_lead_met: true,
      progress:                 true,
    )

    expect(results.fetch("alice").transform_values do |counts|
      counts.fetch(:merged_pr_author)
    end).to eq("Homebrew/brew" => 25, "Homebrew/homebrew-core" => 0, "Homebrew/homebrew-cask" => 100)
  end

  it "uses a GitHub username resolved from a public email address" do
    command = described_class.new(["--user=alice@example.com", "--repositories=Homebrew/untapped"])
    repository = "Homebrew/untapped"
    allow(GitHub).to receive(:search)
      .with("users", "\"alice@example.com\" in:email")
      .and_return({ "items" => [{ "login" => "alice" }] })
    expect(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2026-01-01..2026-01-31")
      .and_return([{ "number" => 123, "repository_url" => "#{GitHub::API_URL}/repos/#{repository}" }])
    expect(GitHub).to receive(:search_approved_pull_requests_in_user_or_organisation)
      .with("Homebrew", "alice", from: "2026-01-01", to: "2026-01-31")
      .and_return([])

    results = command.scan_contributions(
      "Homebrew",
      [repository],
      {},
      { "alice@example.com" => "alice@example.com" },
      from:                     "2026-01-01",
      to:                       "2026-02-01",
      skip_reviews_if_lead_met: false,
      progress:                 false,
    )

    expect(results.fetch("alice@example.com").fetch(repository)).to eq(
      merged_pr_author: 1, merged_pr_merger: 0, merged_pr: 1, approved_pr_review: 0, coauthor: 0,
    )
  end

  it "uses the username embedded in a GitHub no-reply email address" do
    command = described_class.new(["--user=39449589+krehel@users.noreply.github.com"])

    expect(GitHub).not_to receive(:search)
    expect(command.github_username_for("39449589+krehel@users.noreply.github.com", to: "2026-02-01"))
      .to eq("krehel")
  end

  it "counts authored squash-merged PRs in repositories with local Git history" do
    command = described_class.new(["--user=alice", "--repositories=Homebrew/homebrew-core"])
    repository = "Homebrew/homebrew-core"
    repository_refs = { repository => [Pathname("/Homebrew/homebrew-core"), "origin/HEAD"] }
    git_counts = { merged_pr_author: 1, merged_pr_merger: 0, merged_pr: 1, approved_pr_review: 0, coauthor: 0 }
    allow(Utils).to receive(:safe_popen_read).and_return("git log")
    allow(command).to receive(:parse_git_log).and_return("alice" => git_counts)
    allow(GitHub).to receive(:search_approved_pull_requests_in_user_or_organisation).and_return([])
    expect(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2026-01-01..2026-01-31")
      .and_return([
        { "number" => 123, "repository_url" => "#{GitHub::API_URL}/repos/#{repository}" },
        { "number" => 124, "repository_url" => "#{GitHub::API_URL}/repos/#{repository}" },
      ])

    results = command.scan_contributions(
      "Homebrew",
      [repository],
      repository_refs,
      { "alice" => "alice" },
      from:                     "2026-01-01",
      to:                       "2026-02-01",
      skip_reviews_if_lead_met: false,
      progress:                 false,
    )

    expect(results.fetch("alice").fetch(repository)).to eq(
      merged_pr_author: 2, merged_pr_merger: 0, merged_pr: 2, approved_pr_review: 0, coauthor: 0,
    )
  end

  it "counts a self-merged PR once" do
    command = described_class.new(["--user=alice", "--repositories=Homebrew/homebrew-core"])
    repository = "Homebrew/homebrew-core"
    repository_refs = { repository => [Pathname("/Homebrew/homebrew-core"), "origin/HEAD"] }
    separator = Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR
    record_separator = Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR
    merge = [
      "merge", "base pull-request", "Alice", "alice@example.com", "Alice", "alice@example.com",
      "Merge pull request #123 from alice/topic"
    ].join(separator)
    pull_request = [
      "pull-request", "base", "Alice", "alice@example.com", "Alice", "alice@example.com", "Change something"
    ].join(separator)
    git_log = "#{merge}#{record_separator}#{pull_request}#{record_separator}"
    allow(Utils).to receive(:safe_popen_read).and_return(git_log)
    allow(GitHub).to receive(:search_approved_pull_requests_in_user_or_organisation).and_return([])
    expect(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2026-01-01..2026-01-31")
      .and_return([{ "number" => 123, "repository_url" => "#{GitHub::API_URL}/repos/#{repository}" }])

    results = command.scan_contributions(
      "Homebrew",
      [repository],
      repository_refs,
      { "alice" => "Alice" },
      from:                     "2026-01-01",
      to:                       "2026-02-01",
      skip_reviews_if_lead_met: false,
      progress:                 false,
    )

    expect(results.fetch("alice").fetch(repository)).to eq(
      merged_pr_author: 1, merged_pr_merger: 1, merged_pr: 1, approved_pr_review: 0, coauthor: 0,
    )
  end

  it "counts a GitHub-authored PR once when Git only identifies its merger" do
    command = described_class.new(["--user=alice", "--repositories=Homebrew/homebrew-core"])
    repository = "Homebrew/homebrew-core"
    repository_refs = { repository => [Pathname("/Homebrew/homebrew-core"), "origin/HEAD"] }
    separator = Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR
    record_separator = Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR
    merge = [
      "merge", "base pull-request", "Alice", "alice@example.com", "Alice", "alice@example.com",
      "Merge pull request #123 from Homebrew/topic"
    ].join(separator)
    pull_request = [
      "pull-request", "base", "BrewTestBot", "test-bot@example.com", "BrewTestBot", "test-bot@example.com",
      "Change something"
    ].join(separator)
    git_log = "#{merge}#{record_separator}#{pull_request}#{record_separator}"
    allow(Utils).to receive(:safe_popen_read).and_return(git_log)
    allow(GitHub).to receive(:search_approved_pull_requests_in_user_or_organisation).and_return([])
    expect(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2026-01-01..2026-01-31")
      .and_return([{ "number" => 123, "repository_url" => "#{GitHub::API_URL}/repos/#{repository}" }])

    results = command.scan_contributions(
      "Homebrew",
      [repository],
      repository_refs,
      { "alice" => "Alice" },
      from:                     "2026-01-01",
      to:                       "2026-02-01",
      skip_reviews_if_lead_met: false,
      progress:                 false,
    )

    expect(results.fetch("alice").fetch(repository)).to eq(
      merged_pr_author: 1, merged_pr_merger: 1, merged_pr: 1, approved_pr_review: 0, coauthor: 0,
    )
  end

  it "attributes merged PRs once and learns non-Maintainer Git identities" do
    command = described_class.new(["--user=alice"])
    separator = Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR
    record_separator = Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR
    merge = [
      "merge", "base pull-request", "Alice Example", "alice@example.com", "Alice Example", "alice@example.com",
      "Merge pull request #123 from Homebrew/topic"
    ].join(separator)
    pull_request = [
      "pull-request", "base", "Bob Example", "bob@example.com", "Bob Example", "bob@example.com",
      "Change something\n\nCo-authored-by: Alice Example <123+alice@users.noreply.github.com>"
    ].join(separator)
    coauthored = [
      "coauthored", "base", "Someone Else", "someone@example.com", "Someone Else", "someone@example.com",
      "Change another thing\n\nCo-authored-by: Bob Example <bob@example.com>"
    ].join(separator)

    counts = command.parse_git_log(
      "#{merge}#{record_separator}#{pull_request}#{record_separator}#{coauthored}#{record_separator}",
      { "alice" => "Alice Example", "bob" => "bob" },
      github_identities: { "alice" => ["alice@example.com"], "bob" => ["bob", "Bob Example", "bob@example.com"] },
    )

    expect(counts).to eq(
      "alice" => {
        merged_pr_author: 0, merged_pr_merger: 1, merged_pr: 1, approved_pr_review: 0, coauthor: 1
      },
      "bob"   => {
        merged_pr_author: 1, merged_pr_merger: 0, merged_pr: 1, approved_pr_review: 0, coauthor: 1
      },
    )
  end

  it "attributes amended committers as coauthors" do
    command = described_class.new(["--user=alice"])
    separator = Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR
    record_separator = Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR
    base = ["base", "", "Maintainer", "maintainer@example.com", "Maintainer", "maintainer@example.com", "Base"]
           .join(separator)
    amended = [
      "amended", "base", "Alice Example", "alice@example.com", "John", "bob@example.com", "Change something"
    ].join(separator)
    merge = [
      "merge", "base amended", "Alice Example", "alice@example.com", "Joe", "alice@example.com",
      "Merge pull request #123 from Homebrew/topic"
    ].join(separator)

    counts = command.parse_git_log(
      "#{merge}#{record_separator}#{amended}#{record_separator}#{base}#{record_separator}",
      { "alice" => "Alice Example", "bob" => "Bob Example" },
      github_identities: { "alice" => ["alice@example.com"], "bob" => ["bob@example.com"] },
    )

    expect(counts.fetch("bob").fetch(:coauthor)).to eq(1)
  end

  it "matches commits under a GitHub profile's name and email for a username" do
    command = described_class.new(["--user=alice", "--repositories=Homebrew/homebrew-core"])
    repository = "Homebrew/homebrew-core"
    commit = [
      "commit", "base", "Someone Else", "someone@example.com", "Someone Else", "someone@example.com",
      "Change something\n\nCo-authored-by: Alice Example <a.example@example.com>"
    ].join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)
    allow(Utils).to receive(:safe_popen_read)
      .and_return("#{commit}#{Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR}")
    allow(GitHub::API).to receive(:open_rest)
      .with(GitHub.url_to("users", "alice"))
      .and_return({ "name" => "Alice Example", "email" => "a.example@example.com" })
    allow(GitHub).to receive_messages(search_issues: [], search_approved_pull_requests_in_user_or_organisation: [])

    results = command.scan_contributions(
      "Homebrew",
      [repository],
      { repository => [Pathname("/Homebrew/homebrew-core"), "origin/HEAD"] },
      { "alice" => "alice" },
      from:                     "2026-01-01",
      to:                       "2026-02-01",
      skip_reviews_if_lead_met: false,
      progress:                 false,
    )

    expect(results.fetch("alice").fetch(repository).fetch(:coauthor)).to eq(1)
  end

  it "skips GitHub profile names shared by multiple requested users" do
    command = described_class.new(["--user=alice"])
    ambiguous = [
      "ambiguous", "base", "Someone Else", "someone@example.com", "Someone Else", "someone@example.com",
      "Change something\n\nCo-authored-by: Alex <unknown@example.com>"
    ].join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)
    by_email = [
      "by-email", "base", "Someone Else", "someone@example.com", "Someone Else", "someone@example.com",
      "Change another thing\n\nCo-authored-by: Alex <bob@example.com>"
    ].join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)

    counts = command.parse_git_log(
      "#{ambiguous}#{Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR}#{by_email}#{Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR}",
      { "alice" => "alice", "bob" => "bob" },
      github_identities: { "alice" => %w[alice Alex alice@example.com], "bob" => %w[bob Alex bob@example.com] },
    )

    expect(counts.transform_values { |user_counts| user_counts.fetch(:coauthor) }).to eq("alice" => 0, "bob" => 1)
  end

  it "prefers an exact email match over a GitHub profile name" do
    command = described_class.new(["--user=alice"])
    commit = [
      "commit", "base", "Someone Else", "someone@example.com", "Someone Else", "someone@example.com",
      "Change something\n\nCo-authored-by: Alex <bob@example.com>"
    ].join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)

    counts = command.parse_git_log(
      "#{commit}#{Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR}",
      { "alice" => "alice", "bob" => "bob" },
      github_identities: { "alice" => %w[alice Alex alice@example.com], "bob" => %w[bob bob@example.com] },
    )

    expect(counts.transform_values { |user_counts| user_counts.fetch(:coauthor) }).to eq("alice" => 0, "bob" => 1)
  end

  it "matches GitHub no-reply usernames but not other emails' local parts" do
    command = described_class.new(["--user=alice"])
    unrelated = [
      "unrelated", "base", "Someone Else", "someone@example.com", "Someone Else", "someone@example.com",
      "Change something\n\nCo-authored-by: Other Alice <alice@unrelated.example.com>"
    ].join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)
    noreply = [
      "noreply", "base", "Someone Else", "someone@example.com", "Someone Else", "someone@example.com",
      "Change another thing\n\nCo-authored-by: A. Example <123+alice@users.noreply.github.com>"
    ].join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)

    counts = command.parse_git_log(
      "#{unrelated}#{Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR}#{noreply}#{Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR}",
      { "alice" => "Alice Example" },
    )

    expect(counts.fetch("alice").fetch(:coauthor)).to eq(1)
  end

  it "skips approval queries after Git meets the Lead repository thresholds" do
    command = described_class.new(["--user=alice"])
    repositories = {
      "Homebrew/brew"          => [Pathname("/Homebrew/brew"), "origin/HEAD"],
      "Homebrew/homebrew-core" => [Pathname("/Homebrew/homebrew-core"), "origin/HEAD"],
    }
    counts = {
      merged_pr_author: 0, merged_pr_merger: 0, merged_pr: 25, approved_pr_review: 0, coauthor: 0
    }
    allow(Utils).to receive(:safe_popen_read).and_return("")
    allow(command).to receive(:parse_git_log).and_return("alice" => counts)
    allow(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2025-12-01..2026-02-28")
      .and_return([])
    expect(GitHub).not_to receive(:search_approved_pull_requests_in_user_or_organisation)

    expect(command.scan_contributions(
             "Homebrew",
             repositories.keys,
             repositories,
             { "alice" => "Alice" },
             from:                     "2025-12-01",
             to:                       "2026-03-01",
             skip_reviews_if_lead_met: true,
             progress:                 true,
           )).to eq("alice" => { "Homebrew/brew" => counts, "Homebrew/homebrew-core" => counts })
  end

  it "scopes capped review searches by repository until Lead activity is known" do
    command = described_class.new(["--user=alice"])
    repositories = Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
      [repository, [Pathname("/#{repository}"), "origin/HEAD"]]
    end
    no_contributions = {
      merged_pr_author: 0, merged_pr_merger: 0, merged_pr: 0, approved_pr_review: 0, coauthor: 0
    }
    allow(Utils).to receive(:safe_popen_read).and_return("brew", "core", "cask")
    allow(command).to receive(:parse_git_log) do |output, _|
      { "alice" => (output == "cask") ? no_contributions.merge(coauthor: 500) : no_contributions.dup }
    end
    allow(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2025-12-01..2026-02-28")
      .and_return([])
    allow(GitHub).to receive(:search_approved_pull_requests_in_user_or_organisation)
      .with("Homebrew", "alice", from: "2025-12-01", to: "2026-02-28")
      .and_return(Array.new(100) do
        { "repository_url" => "#{GitHub::API_URL}/repos/Homebrew/homebrew-cask" }
      end)
    expect(GitHub).to receive(:search_issues)
      .with("", is: "pr", review: "approved", repo: "Homebrew/brew", reviewed_by: "alice",
            from: "2025-12-01", to: "2026-02-28")
      .and_return(Array.new(25) { {} })

    results = command.scan_contributions(
      "Homebrew",
      repositories.keys,
      repositories,
      { "alice" => "Alice" },
      from:                     "2025-12-01",
      to:                       "2026-03-01",
      skip_reviews_if_lead_met: true,
      progress:                 true,
    )

    expect(results.fetch("alice").transform_values do |counts|
      counts.fetch(:approved_pr_review)
    end).to eq("Homebrew/brew" => 25, "Homebrew/homebrew-core" => 0, "Homebrew/homebrew-cask" => 100)
  end

  it "excludes the end date from approved review searches" do
    command = described_class.new(["--user=alice"])
    repositories = Homebrew::DevCmd::Contributions::PRIMARY_REPOS.to_h do |repository|
      [repository, [Pathname("/#{repository}"), "origin/HEAD"]]
    end
    counts = {
      merged_pr_author: 0, merged_pr_merger: 0, merged_pr: 0, approved_pr_review: 0, coauthor: 0
    }
    allow(Utils).to receive(:safe_popen_read).and_return("")
    allow(command).to receive(:parse_git_log) do
      { "alice" => counts.dup }
    end
    allow(GitHub).to receive(:search_issues)
      .with("", is: "merged", user: "Homebrew", author: "alice", merged: "2025-12-01..2026-02-28")
      .and_return([])
    allow(GitHub).to receive(:search_approved_pull_requests_in_user_or_organisation)
      .with("Homebrew", "alice", from: "2025-12-01", to: "2026-02-28")
      .and_return([
        { "repository_url" => "#{GitHub::API_URL}/repos/Homebrew/brew" },
        { "repository_url" => "#{GitHub::API_URL}/repos/Homebrew/homebrew-core" },
      ])

    results = command.scan_contributions(
      "Homebrew",
      repositories.keys,
      repositories,
      { "alice" => "Alice" },
      from:                     "2025-12-01",
      to:                       "2026-03-01",
      skip_reviews_if_lead_met: true,
      progress:                 true,
    )

    expect(results.transform_values do |repository_counts|
      repository_counts.transform_values { |repository_count| repository_count.fetch(:approved_pr_review) }
    end).to eq("alice" => {
      "Homebrew/brew" => 1, "Homebrew/homebrew-core" => 1, "Homebrew/homebrew-cask" => 0
    })
  end

  context "when scanning maintainer activity" do
    # Keep each Sorbet signature with its let declaration.
    # rubocop:disable RSpec/ScatteredLet
    sig { returns(Homebrew::DevCmd::Contributions) }
    let(:command) { described_class.new(["--maintainer-report-csv=2026-1"]) }

    sig { returns(T::Array[String]) }
    let(:repositories) { %w[Homebrew/brew Homebrew/homebrew-core] }

    sig { returns(T::Hash[Symbol, Integer]) }
    let(:counts) { { merged_pr_merger: 25, approved_pr_review: 0, closed_issue: 0 } }
    # rubocop:enable RSpec/ScatteredLet

    before do
      allow(Utils).to receive(:safe_popen_read).and_return("")
      allow(command).to receive(:parse_git_log) { { "alice" => counts.dup } }
      allow(command).to receive_messages(github_identities_for_username: ["alice"], closed_issue_counts: {})
    end

    it "excludes self-merges even when another person authored the last commit" do
      allow(command).to receive(:parse_git_log).and_call_original
      output = [
        ["merge", "base tip", "Alice", "alice@example.com", "Alice", "alice@example.com",
         "Merge pull request #123 from Homebrew/topic"],
        ["tip", "base", "Bot", "bot@example.com", "Bot", "bot@example.com", "Change something"],
      ].map { |fields| fields.join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR) }
       .join(Homebrew::DevCmd::Contributions::GIT_LOG_RECORD_SEPARATOR)
      allow(Utils).to receive(:safe_popen_read).and_return(output)
      allow(GitHub::API).to receive(:open_graphql)
        .and_return({ "data" => { "repository" => { "pr123" => { "author" => { "login" => "alice" } } } } })
      allow(GitHub::API).to receive(:open_rest).with(an_instance_of(URI::HTTPS)) do |uri|
        if URI.decode_www_form(uri.query.to_s).to_h.fetch("q").include?("reviewed-by:")
          { "items" => [], "total_count" => 0 }
        else
          { "items" => [{ "number" => 123 }], "total_count" => 1 }
        end
      end

      results = command.scan_contributions(
        "Homebrew",
        ["Homebrew/brew"], { "Homebrew/brew" => [Pathname("/Homebrew/brew"), "origin/HEAD"] },
        { "alice" => "Alice" }, from: "2026-01-01", to: "2026-02-01",
        skip_reviews_if_lead_met: true, progress: false
      )

      expect(results.fetch("alice").fetch("Homebrew/brew").fetch(:merged_pr_merger)).to eq(0)
    end

    it "caches unavailable PRs and stops once enough non-self merges are verified" do
      calls = 0
      allow(GitHub::API).to receive(:open_graphql).with(anything, variables: anything, raise_errors: false) do
        calls += 1
        { "data"   => { "repository" => (1..100).to_h do |number|
          next ["pr1", nil] if number == 1

          ["pr#{number}", { "author" => { "login" => (number <= 50) ? "ALICE" : "bob" } }]
        end },
          "errors" => [{ "type" => "NOT_FOUND", "path" => ["repository", "pr1"], "message" => "PR unavailable" }] }
      end
      allow(GitHub::API).to receive(:open_rest).and_raise("Unexpected API search")
      results = Array.new(2) do
        command.scan_maintainer_contributions(
          ["Homebrew/brew"], { "alice" => { "Homebrew/brew" => counts.dup } }, { "alice" => "alice" },
          { "alice" => { "Homebrew/brew" => (1..2000).to_set(&:to_s) } },
          from: "2026-01-01", to: "2026-02-01", skip_reviews_if_lead_met: true, progress: false
        ).fetch("alice").fetch("Homebrew/brew").values_at(:merged_pr_merger, :merges_skipped)
      end

      expect([results, calls]).to eq([[[50, 1], [50, 1]], 1])
    end

    it "does not assess inactivity when an unavailable PR could change the result" do
      allow(GitHub::API).to receive_messages(open_graphql: { "data" => {
        "repository" => (1..40).to_h do |number|
          ["pr#{number}", (number == 1) ? nil : { "author" => { "login" => "bob" } }]
        end,
      } }, open_rest: { "items" => [], "total_count" => 0 })

      expect do
        command.scan_maintainer_contributions(
          ["Homebrew/brew"], { "alice" => { "Homebrew/brew" => counts.dup } }, { "alice" => "alice" },
          { "alice" => { "Homebrew/brew" => (1..40).to_set(&:to_s) } },
          from: "2026-01-01", to: "2026-02-01", skip_reviews_if_lead_met: true, progress: false
        )
      end.to raise_error(SystemExit).and output(/unavailable PRs could change the activity assessment/).to_stderr
    end

    it "propagates API errors unrelated to individual missing PRs" do
      allow(GitHub::API).to receive(:open_graphql).and_return({
        "data"   => { "repository" => nil },
        "errors" => [{ "type" => "NOT_FOUND", "path" => ["repository"], "message" => "Repository unavailable" }],
      })

      expect do
        command.scan_maintainer_contributions(
          ["Homebrew/brew"], { "alice" => { "Homebrew/brew" => counts.dup } }, { "alice" => "alice" },
          { "alice" => { "Homebrew/brew" => Set["123"] } },
          from: "2026-01-01", to: "2026-02-01", skip_reviews_if_lead_met: true, progress: false
        )
      end.to raise_error(GitHub::API::Error, "Repository unavailable")
    end

    it "skips review queries when merges already meet both repository thresholds" do
      expect(command).not_to receive(:approved_pull_request?)
      command.scan_contributions(
        "Homebrew",
        repositories, repositories.to_h { |repo| [repo, [Pathname("/#{repo}"), "origin/HEAD"]] },
        { "alice" => "Alice" }, from: "2026-01-01", to: "2026-02-01",
        skip_reviews_if_lead_met: true, progress: false
      )
    end

    it "stops verifying approvals once confirmed contributions meet the thresholds" do
      counts[:merged_pr_merger] = 19
      allow(GitHub::API).to receive(:open_rest).with(an_instance_of(URI::HTTPS)).and_return(
        { "items" => [{ "number" => 123 }, { "number" => 124 }, { "number" => 125 }], "total_count" => 3 },
      )
      allow(command).to receive(:approved_pull_request?).and_return(true)

      results = command.scan_contributions(
        "Homebrew",
        repositories, repositories.to_h { |repo| [repo, [Pathname("/#{repo}"), "origin/HEAD"]] },
        { "alice" => "Alice" }, from: "2026-01-01", to: "2026-02-01",
        skip_reviews_if_lead_met: true, progress: false
      )

      expect(results.fetch("alice").transform_values { |result| result.fetch(:approved_pr_review) })
        .to eq("Homebrew/brew" => 2, "Homebrew/homebrew-core" => 1)
    end

    it "continues onto later candidate pages when earlier matches are not approvals" do
      allow(GitHub::API).to receive(:open_rest).with(an_instance_of(URI::HTTPS)) do |uri|
        { "items" => [{ "number" => uri.query.include?("page=2") ? 124 : 123 }], "total_count" => 101 }
      end
      allow(command).to receive(:approved_pull_request?) { |_, number, *_args| number == 124 }

      results = command.scan_maintainer_contributions(
        ["Homebrew/brew"],
        { "alice" => { "Homebrew/brew" => { merged_pr_merger: 0, approved_pr_review: 0, closed_issue: 0 } } },
        { "alice" => "alice" }, { "alice" => { "Homebrew/brew" => Set.new } },
        from: "2026-01-01", to: "2026-02-01", skip_reviews_if_lead_met: false, progress: false
      )

      expect(results.fetch("alice").fetch("Homebrew/brew").fetch(:approved_pr_review)).to eq(1)
    end

    it "does not count a review again when the same maintainer merged the PR" do
      allow(GitHub::API).to receive(:open_graphql)
        .and_return({ "data" => { "repository" => { "pr123" => { "author" => { "login" => "bob" } } } } })
      allow(command).to receive(:parse_git_log) do |_, _, merger_pull_requests:, **_kwargs|
        merger_pull_requests.fetch("alice") << "123"
        { "alice" => counts.dup }
      end
      allow(GitHub::API).to receive(:open_rest).with(an_instance_of(URI::HTTPS)) do |uri|
        if URI.decode_www_form(uri.query.to_s).to_h.fetch("q").include?("reviewed-by:")
          { "items" => [{ "number" => 123 }], "total_count" => 1 }
        else
          { "items" => [], "total_count" => 0 }
        end
      end
      expect(command).not_to receive(:approved_pull_request?)

      command.scan_contributions(
        "Homebrew",
        ["Homebrew/brew"], { "Homebrew/brew" => [Pathname("/Homebrew/brew"), "origin/HEAD"] },
        { "alice" => "Alice" }, from: "2026-01-01", to: "2026-02-01",
        skip_reviews_if_lead_met: false, progress: false
      )
    end

    it "rejects incomplete candidate searches before reporting inactivity" do
      allow(GitHub::API).to receive(:open_rest).with(an_instance_of(URI::HTTPS)).and_return(
        { "items" => [], "total_count" => 0, "incomplete_results" => true },
      )

      expect do
        command.scan_contributions(
          "Homebrew",
          ["Homebrew/brew"], {}, { "alice" => "Alice" },
          from: "2026-01-01", to: "2026-02-01", skip_reviews_if_lead_met: true, progress: false
        )
      end.to raise_error(SystemExit)
    end

    it "counts issue closures towards the activity thresholds" do
      allow(command).to receive(:closed_issue_counts).and_return("alice" => 25)
      expect(command).not_to receive(:approved_pull_request?)

      command.scan_contributions(
        "Homebrew",
        repositories, {}, { "alice" => "Alice" },
        from: "2026-01-01", to: "2026-02-01", skip_reviews_if_lead_met: true, progress: false
      )
    end
  end

  it "reuses all API responses for an identical completed-period maintainer scan" do
    output = ["merge", "base tip", "Alice", "alice@example.com", "Alice", "alice@example.com",
              "Merge pull request #123 from bob/topic"]
             .join(Homebrew::DevCmd::Contributions::GIT_LOG_FIELD_SEPARATOR)
    allow(Utils).to receive(:safe_popen_read).and_return(output)
    allow(GitHub::API).to receive_messages(
      open_rest:    { "items" => [{ "number" => 456 }], "total_count" => 1 },
      open_graphql: { "data" => { "repository" => { "pr123" => { "author" => { "login" => "bob" } } } } },
    )
    allow(GitHub::API).to receive(:paginate_graphql) do |query, **_kwargs, &block|
      if query.include?("issues(")
        block.call("repository" => { "issues" => { "nodes" => [], "pageInfo" => { "hasNextPage" => false } } })
      else
        block.call("repository" => { "pullRequest" => {
          "mergedAt" => "2026-01-20T00:00:00Z", "author" => { "login" => "bob" },
          "timelineItems" => {
            "nodes"    => [{ "id" => "review", "author" => { "login" => "alice" },
                          "submittedAt" => "2026-01-15T12:00:00Z", "state" => "APPROVED",
                          "authorCanPushToRepository" => true }],
            "pageInfo" => { "hasNextPage" => false },
          }
        } })
      end
    end
    scan = lambda do
      described_class.new(["--maintainer-report-csv=2026-1"]).scan_contributions(
        "Homebrew", ["Homebrew/brew"], { "Homebrew/brew" => [Pathname("/Homebrew/brew"), "origin/HEAD"] },
        { "alice" => "Alice" }, from: "2026-01-01", to: "2026-02-01",
        skip_reviews_if_lead_met: true, progress: false
      )
    end
    scan.call
    [:open_rest, :open_graphql, :paginate_graphql].each do |method|
      allow(GitHub::API).to receive(method).and_raise("Unexpected API call on a cached rerun")
    end

    expect(scan.call.fetch("alice").fetch("Homebrew/brew"))
      .to eq(merged_pr_merger: 1, approved_pr_review: 1, closed_issue: 0)
  end

  it "rejects historical reports using the old contribution criteria" do
    command = described_class.new([])
    result = Dir.chdir(mktmpdir) do
      Pathname("brew-contributions-2026-01-01-to-2026-02-01.csv")
        .write("username,brew issues closed,brew total,core total,cask total\nAlice,0,50,50,0\n")
      command.maintainer_activity_report("2026-01-01", "2026-02-01")
    end

    expect(result).to be_nil
  end

  it "caches completed GitHub searches in the prunable Homebrew cache" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    results = [{ "repository_url" => "#{GitHub::API_URL}/repos/Homebrew/brew" }]
    calls = 0

    2.times do
      expect(command.cached_github_request(Array, "approved", "Homebrew", "alice", "2026-1", to: "2026-03-01") do
        calls += 1
        results
      end).to eq(results)
    end

    expect(calls).to eq(1)
    cache_file = HOMEBREW_CACHE.children.fetch(0)
    expect(cache_file.basename.to_s).to match(/\Acontributions--[a-f\d]{64}\.json\z/)

    expect do
      Homebrew::Cleanup.new(days: 0, cache: HOMEBREW_CACHE)
                       .cleanup_cache([{ path: cache_file, type: nil }], cleanup_unreferenced: false)
    end.to output(/Removing:/).to_stdout
    expect(cache_file).not_to exist
  end

  it "backs off secondary limits and stops after three retries" do
    command = described_class.new([])
    error = GitHub::API::RateLimitExceededError.new("Secondary rate limit", reset: 0, resource: "secondary", limit: 0)
    delays = []
    calls = 0
    allow(GitHub::API).to receive(:sleep_for_rate_limit) do |_, minimum:|
      delays << minimum
      raise "Too many retries" if delays.length > 3
    end
    begin
      command.cached_github_request(Array, "limited", to: "2026-03-01") do
        calls += 1
        raise error
      end
    rescue GitHub::API::RateLimitExceededError
      # Exhausted retries must propagate to the caller.
    end

    expect([calls, delays]).to eq([4, [60, 120, 240]])
  end

  it "warns about unreadable cache files before deleting them" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    command.cached_github_request(Array, "approved", to: "2026-03-01") { [] }
    HOMEBREW_CACHE.children.fetch(0).write("not json")

    expect do
      command.cached_github_request(Array, "approved", to: "2026-03-01") { [] }
    end.to output(/Deleting unreadable contributions cache/).to_stderr
  end

  it "warns about cached results of an unexpected type before deleting them" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    command.cached_github_request(Hash, "user-profile", to: "2026-03-01") { {} }

    expect do
      command.cached_github_request(Array, "user-profile", to: "2026-03-01") { [] }
    end.to output(/Deleting contributions cache .* containing Hash rather than Array/).to_stderr
  end

  it "caches GitHub profile lookups" do
    command = described_class.new(["--user=alice"])
    expect(GitHub::API).to receive(:open_rest)
      .with(GitHub.url_to("users", "alice"))
      .once
      .and_return({ "name" => "Alice Example", "email" => "alice@example.com" })

    identities = Array.new(2) { command.github_identities_for_username("alice", to: "2026-03-01") }

    expect(identities).to eq([["alice", "Alice Example", "alice@example.com"]] * 2)
  end

  it "retains former usernames as Git identities in maintainer reports" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])

    expect(command.github_identities_for_username("branchv", to: "2026-03-01"))
      .to eq(["branchv", "branchvincent"])
  end

  it "resolves requested former usernames only in maintainer mode" do
    expect([[], ["--maintainer-report-csv=2026-1"]].map do |arguments|
      described_class.new(arguments).github_username_for("branchvincent", to: "2026-03-01")
    end).to eq(["branchvincent", "branchv"])
  end

  it "returns only the username for a missing GitHub profile" do
    command = described_class.new(["--user=alice"])
    allow(GitHub::API).to receive(:open_rest).and_raise(GitHub::API::HTTPNotFoundError, "Not Found")

    expect(command.github_identities_for_username("alice", to: "2026-03-01")).to eq(["alice"])
  end
end
