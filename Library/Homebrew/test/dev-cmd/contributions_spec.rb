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

  it "documents the governance reporting quarters" do
    help_text = described_class.parser.generate_help_text.gsub(/\s+/, " ")

    expect(help_text).to include(
      "--maintainer-report-csv=2026-2",
      "current directory",
      "brew-contributions-FROM-to-TO-USER.csv",
      "Only Maintainers listed at the end of that quarter are included",
      "Completed-period GitHub searches are cached in Homebrew's cache",
      "Repository-scoped follow-up searches ensure role activity checks remain accurate",
      "YEAR-1 is December of the previous year through February",
      "YEAR-2 is March through May",
      "YEAR-3 is June through August",
      "YEAR-4 is September through November",
    )
  end

  it "uses the first README mention for Maintainer tenure" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    repository_path = Pathname("/Homebrew/brew")
    allow(Utils).to receive(:safe_popen_read).and_return("")
    allow(Utils).to receive(:safe_popen_read)
      .with(Utils::Git.git, "-C", repository_path, "log", "quarter-end-ref", "--fixed-strings",
            "-SAlice", "--format=%H%x1f%cs", "--", "README.md")
      .and_return("first-mention\x1f2020-01-02\n")
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

  it "reads historical Maintainer lists" do
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
        Homebrew's maintainers are [Alice](https://github.com/alice) and [Bob](https://github.com/bob).
        Former maintainers include [Carol](https://github.com/carol).
      MARKDOWN
    allow(command).to receive(:maintainer_since).and_return("2020-01-02")

    expect(command.maintainer_report_users(repository_refs, "2025-09-01")).to eq([
      { "alice" => "Alice", "bob" => "Bob" }, {}, { "alice" => "2020-01-02", "bob" => "2020-01-02" }
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
        Error: Not listed as Maintainers at the end of the reporting quarter: carol and dave.
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
    no_contributions = { merged_pr_author: 0, merged_pr_merger: 0, merged_pr: 0, approved_pr_review: 0, coauthor: 0 }
    alice_results = {
      "Homebrew/brew"          => {
        merged_pr_author: 2, merged_pr_merger: 3, merged_pr: 4, approved_pr_review: 1, coauthor: 45
      },
      "Homebrew/homebrew-core" => no_contributions,
      "Homebrew/homebrew-cask" => no_contributions,
    }
    bob_results = {
      "Homebrew/brew"          => {
        merged_pr_author: 25, merged_pr_merger: 1, merged_pr: 25, approved_pr_review: 0, coauthor: 0
      },
      "Homebrew/homebrew-core" => {
        merged_pr_author: 24, merged_pr_merger: 0, merged_pr: 24, approved_pr_review: 1, coauthor: 0
      },
      "Homebrew/homebrew-cask" => no_contributions.merge(coauthor: 451),
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
      username,name,since,tenure days,brew authored,brew merged,brew PRs,brew reviews,brew coauthored,brew total,core authored,core merged,core PRs,core reviews,core coauthored,core total,cask authored,cask merged,cask PRs,cask reviews,cask coauthored,cask total,total,maintainer met,lead met,capped,role,potential new role
      bob,Bob,2022-03-01,1461,25,1,25,0,0,25,24,0,24,1,0,25,0,0,0,0,451,451,501,true,true,false,Maintainer,Maintainer
      alice,Alice,2024-03-01,730,2,3,4,1,45,50,0,0,0,0,0,0,0,0,0,0,0,0,50,true,false,false,Lead Maintainer,Lead Maintainer
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
        "2025-09-01-to-2025-12-01" => [true, true],
        "2025-06-01-to-2025-09-01" => [true, false],
        "2025-03-01-to-2025-06-01" => [false, false],
      }.each do |dates, activity|
        Pathname("brew-contributions-#{dates}.csv")
          .write("username,maintainer met,lead met\nAlice,#{activity.join(",")}\n")
      end

      command.previous_maintainer_reports("2025-12-01")
    end

    expect(reports).to eq([
      { "alice" => [true, true] },
      { "alice" => [true, false] },
      { "alice" => [false, false] },
    ])
  end

  it "warns when the immediately preceding report is unavailable" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])

    expect do
      expect(Dir.chdir(mktmpdir) { command.previous_maintainer_reports("2025-12-01") }).to be_empty
    end.to output(<<~EOS).to_stderr
      Warning: Could not find brew-contributions-2025-09-01-to-2025-12-01.csv; omitting the potential new role column.
    EOS
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
      merged_pr_author: 0, merged_pr_merger: 0, merged_pr: 0, approved_pr_review: 0, coauthor: 0
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
    command = described_class.new(["--maintainer-report-csv=2026-1"])
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
      .with("Homebrew", "alice", from: "2026-01-01", to: "2026-02-01")
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
    separator = "\x1f"
    record_separator = "\x1e"
    merge = [
      "merge", "base pull-request", "Alice", "alice@example.com",
      "Merge pull request #123 from alice/topic"
    ].join(separator)
    pull_request = ["pull-request", "base", "Alice", "alice@example.com", "Change something"].join(separator)
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
    separator = "\x1f"
    record_separator = "\x1e"
    merge = [
      "merge", "base pull-request", "Alice", "alice@example.com",
      "Merge pull request #123 from Homebrew/topic"
    ].join(separator)
    pull_request = ["pull-request", "base", "BrewTestBot", "test-bot@example.com", "Change something"].join(separator)
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
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    separator = "\x1f"
    record_separator = "\x1e"
    merge = [
      "merge", "base pull-request", "Alice Example", "alice@example.com",
      "Merge pull request #123 from Homebrew/topic"
    ].join(separator)
    pull_request = [
      "pull-request", "base", "Bob Example", "bob@example.com",
      "Change something\n\nCo-authored-by: Alice Example <123+alice@users.noreply.github.com>"
    ].join(separator)
    coauthored = [
      "coauthored", "base", "Someone Else", "someone@example.com",
      "Change another thing\n\nCo-authored-by: Bob Example <bob@example.com>"
    ].join(separator)

    counts = command.parse_git_log(
      "#{merge}#{record_separator}#{pull_request}#{record_separator}#{coauthored}#{record_separator}",
      { "alice" => "Alice Example", "bob" => "bob" },
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

  it "skips approval queries after Git meets the Lead repository thresholds" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
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
    command = described_class.new(["--maintainer-report-csv=2026-1"])
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
      .with("Homebrew", "alice", from: "2025-12-01", to: "2026-03-01")
      .and_return(Array.new(100) do
        { "repository_url" => "#{GitHub::API_URL}/repos/Homebrew/homebrew-cask" }
      end)
    expect(GitHub).to receive(:search_issues)
      .with("", is: "pr", review: "approved", repo: "Homebrew/brew", reviewed_by: "alice",
            from: "2025-12-01", to: "2026-03-01")
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

  it "uses the existing approved review search" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
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
      .with("Homebrew", "alice", from: "2025-12-01", to: "2026-03-01")
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

  it "caches completed GitHub searches in the prunable Homebrew cache" do
    command = described_class.new(["--maintainer-report-csv=2026-1"])
    results = [{ "repository_url" => "#{GitHub::API_URL}/repos/Homebrew/brew" }]
    calls = 0

    2.times do
      cache_key = %w[approved Homebrew alice 2026-1].join("\0")
      expect(command.github_search_with_rate_limit(cache_key, to: "2026-03-01") do
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
end
