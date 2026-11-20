# typed: strict
# frozen_string_literal: true

require "utils/analytics/api"

RSpec.describe Utils::Analytics::API do
  before do
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  it "generates Homebrew environment configuration analytics" do
    expect(Utils::Analytics::API::CATEGORIES).to include("homebrew-env-config")
  end

  it "replaces InfluxDB reports without deleting security or Git reports" do
    stub_const("Utils::Analytics::API::CATEGORIES", %w[core-install os-version])
    stub_const("Utils::Analytics::API::DAYS", ["30"])
    influx = instance_double(Utils::Analytics::Influx, setup_python: nil, venv_python: Pathname("python"),
                             influxdb_query_script: Pathname("query.py"), query: [{ total_count: 42 }])
    allow(Utils::Analytics::Influx).to receive(:new).and_return(influx)
    allow(SystemCommand).to receive(:safe_system).with(Pathname("python"), Pathname("query.py"), "--check")
    generator = described_class.new
    allow(generator).to receive_messages(generate_repositories: nil, generate_releases: nil,
                                         generate_formula_history: nil, generate_github_packages: nil)
    mktmpdir.cd do
      Utils::Analytics.write_api("security", "corpus", { count: 1 })
      Utils::Analytics.write_api("security", "current", { count: 2 })
      Utils::Analytics.write_api("github", "history", { count: 3 })
      Utils::Analytics.write_api("install", "obsolete", { count: 4 })
      generator.generate

      expect(Dir.glob("{_data,api}/analytics/**/*.json"))
        .to contain_exactly("_data/analytics/install/homebrew-core/30d.json", "_data/analytics/os-version/30d.json",
                            "api/analytics/install/homebrew-core/30d.json", "api/analytics/os-version/30d.json",
                            "_data/analytics/security/corpus.json", "_data/analytics/security/current.json",
                            "api/analytics/security/corpus.json", "api/analytics/security/current.json",
                            "_data/analytics/github/history.json", "api/analytics/github/history.json")
    end
  end

  it "compares package downloads with matching core install analytics" do
    ENV.delete("HOMEBREW_NO_INSTALL_FROM_API")
    allow(CoreTap.instance).to receive_messages(installed?: true, formula_dir: mktmpdir)
    (CoreTap.instance.formula_dir/"wget.rb").write("")
    (CoreTap.instance.formula_dir/"missing.rb").write("")
    allow(Homebrew::API::Formula).to receive(:all_formulae).and_return({ "api-only" => {} })
    allow(GitHubPackages).to receive(:downloads).with("missing").and_return(nil)
    allow(GitHubPackages).to receive(:downloads).with("wget").and_return(
      GitHubPackages::Downloads.new(source: "https://github.com/example", all_time: 10_000,
                                    last_30_days: 1500, start_date: "2026-09-24", end_date: "2026-10-23",
                                    fetched_at: "2026-10-23T12:00:00Z"),
    )
    mktmpdir.cd do
      Pathname("_data/analytics/install/homebrew-core").mkpath
      Pathname("_data/analytics/install/homebrew-core/30d.json").write(JSON.generate({
        start_date: "2026-09-23", end_date: "2026-10-23",
        formulae: { "wget" => [{ count: "700" }, { count: "50" }] }
      }))
      described_class.new.generate_github_packages

      expect(JSON.parse(Pathname("_data/analytics/github-packages/30d.json").read)).to include(
        "totals"               => { "all_time" => 10_000, "last_30_days" => 1500, "analytics_30d" => 750,
                      "analytics_ratio" => 2.0 },
        "unavailable_formulae" => ["missing"],
        "formulae"             => { "wget" => include("analytics_30d"   => 750,
                                                      "analytics_ratio" => 2.0,
                                                      "all_time"        => 10_000) },
      )
    end
  end

  it "counts PRs and issues separately without the search pagination limit" do
    allow(GitHub::API).to receive(:open_rest).with(
      /q=repo%3AHomebrew%2Fbrew\+is%3Apr\+created%3A2025-10-23\.\.2026-10-22&per_page=1\z/,
    ).and_return({ "total_count" => 2000, "incomplete_results" => false })
    allow(GitHub::API).to receive(:open_rest).with(
      /q=repo%3AHomebrew%2Fbrew\+is%3Aissue\+created%3A2025-10-23\.\.2026-10-22&per_page=1\z/,
    ).and_return({ "total_count" => 123, "incomplete_results" => false })

    expect(described_class.new.github_activity("Homebrew/brew", from: "2025-10-23", to: "2026-10-23"))
      .to include("pull_requests_opened" => 2000, "issues_opened" => 123)
  end

  it "increments completed-day PR and issue counts from a shared paginated list" do
    cache = HOMEBREW_CACHE/"analytics/github/Homebrew/brew/2026-01-01-2026-10-23.json"
    cache.dirname.mkpath
    cache.write(JSON.generate({ "pull_requests_opened" => 100, "issues_opened" => 20,
                                "github_fetched_at" => "2026-10-23T02:00:00Z" }))
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24, 2))
    allow(GitHub::API).to receive(:open_rest).with(%r{/repos/Homebrew/brew/issues\?})
                                             .and_return([
                                               { "number" => 104, "created_at" => "2026-10-24T01:00:00Z" },
                                               { "number" => 103, "created_at" => "2026-10-23T12:00:00Z",
                                                 "pull_request" => {} },
                                               { "number" => 102, "created_at" => "2026-10-23T10:00:00Z" },
                                               { "number" => 101, "created_at" => "2026-10-22T12:00:00Z" },
                                             ])

    expect(described_class.new.github_activity("Homebrew/brew", from: "2026-01-01", to: "2026-10-24"))
      .to include("pull_requests_opened" => 101, "issues_opened" => 21, "github_queries" => 1)
  end

  it "falls back within twice the search-only budget" do
    cache = HOMEBREW_CACHE/"analytics/github/Homebrew/brew/2026-01-01-2026-10-23.json"
    cache.dirname.mkpath
    cache.write(JSON.generate({ "pull_requests_opened" => 100, "issues_opened" => 20,
                                "github_fetched_at" => "2026-10-23T02:00:00Z" }))
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24, 2))
    pages = []
    allow(GitHub::API).to receive(:open_rest) do |url|
      pages << url
      if url.include?("/search/issues?")
        { "total_count" => 200, "incomplete_results" => false }
      else
        Array.new(100) { |i| { "number" => i, "created_at" => "2026-10-23T12:00:00Z" } }
      end
    end
    counts = described_class.new.github_activity("Homebrew/brew", from: "2026-01-01", to: "2026-10-24")

    expect([pages.size, counts]).to match([4, include("pull_requests_opened" => 200, "issues_opened" => 200,
                                                      "github_queries" => 4, "github_method" => "search baseline")])
  end

  it "counts a record only once when new records shift the pagination boundary" do
    cache = HOMEBREW_CACHE/"analytics/github/Homebrew/brew/2026-01-01-2026-10-23.json"
    cache.dirname.mkpath
    cache.write(JSON.generate({ "pull_requests_opened" => 100, "issues_opened" => 20,
                                "github_fetched_at" => "2026-10-23T02:00:00Z" }))
    page = Array.new(100) { |i| { "number" => i, "created_at" => "2026-10-23T12:00:00Z" } }
    allow(GitHub::API).to receive(:open_rest).with(%r{/repos/Homebrew/brew/issues\?})
                                             .and_return(page, [page.last])

    expect(described_class.new.github_activity("Homebrew/brew", from: "2026-01-01", to: "2026-10-24"))
      .to include("pull_requests_opened" => 100, "issues_opened" => 120, "github_queries" => 2)
  end

  it "reads release announcements and disclosures from tracked brew.sh posts" do
    command = described_class.new(homebrew_site: "/example/brew.sh")
    allow(Utils).to receive(:safe_popen_read)
      .with("git", "-C", "/example/brew.sh", "ls-tree", "-r", "--name-only", "HEAD", "--", "_posts")
      .and_return("_posts/2026-09-13-homebrew-7.0.0.md\n_posts/2018-08-05-security-incident-disclosure.md\n" \
                  "_posts/2024-07-30-homebrew-security-audit.md\n")

    expect(command.blog_posts).to eq([
      { "date" => "2026-09-13", "url" => "https://brew.sh/2026/09/13/homebrew-7.0.0/", "version" => "7.0.0" },
      { "date" => "2018-08-05", "url" => "https://brew.sh/2018/08/05/security-incident-disclosure/" },
    ])
  end

  it "rejects incomplete GitHub counts" do
    allow(GitHub::API).to receive(:open_rest).and_return({ "total_count" => 100, "incomplete_results" => true })

    expect { described_class.new.github_activity("Homebrew/brew", from: "2025-10-23", to: "2026-10-23") }
      .to raise_error(RuntimeError, /Incomplete GitHub search/)
  end

  it "reconciles ended years with searches even when daily counts are cached" do
    cache = HOMEBREW_CACHE/"analytics/github/Homebrew/brew/2026-01-01-2026-12-31.json"
    cache.dirname.mkpath
    cache.write(JSON.generate({ "pull_requests_opened" => 100, "issues_opened" => 20,
                                "github_fetched_at" => "2026-12-31T02:00:00Z" }))
    allow(Time).to receive(:now).and_return(Time.utc(2027, 1, 1, 2))
    allow(GitHub::API).to receive(:open_rest).with(%r{/search/issues\?})
                                             .and_return({ "total_count" => 123, "incomplete_results" => false })

    expect(described_class.new.github_activity("Homebrew/brew", from: "2026-01-01", to: "2027-01-01"))
      .to include("pull_requests_opened" => 123, "issues_opened" => 123, "github_queries" => 2)
  end

  it "keeps completed years cached on a later day" do
    command = described_class.new
    allow(GitHub::API).to receive(:open_rest).and_return({ "total_count" => 123, "incomplete_results" => false })
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 23))
    command.github_activity("Homebrew/brew", from: "2025-01-01", to: "2026-01-01")
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24))
    expect(GitHub::API).not_to receive(:open_rest)

    command.github_activity("Homebrew/brew", from: "2025-01-01", to: "2026-01-01")
  end

  it "ranks the download subset using total install events, with deterministic ties" do
    expect(described_class.new.download_formula_names({ "z" => 10, "b" => 100, "a" => 100 }, limit: 2))
      .to eq(%w[a b])
  end

  it "refreshes the last day's partial snapshot before freezing an annual count" do
    command = described_class.new
    allow(Time).to receive(:now).and_return(Time.utc(2026, 12, 31, 12))
    allow(GitHub::API).to receive(:open_rest).and_return({ "total_count" => 123, "incomplete_results" => false })
    command.github_activity("Homebrew/brew", from: "2026-01-01", to: "2027-01-01")
    allow(Time).to receive(:now).and_return(Time.utc(2027, 1, 1, 2))
    allow(GitHub::API).to receive(:open_rest).and_return({ "total_count" => 150, "incomplete_results" => false })

    expect(command.github_activity("Homebrew/brew", from: "2026-01-01", to: "2027-01-01"))
      .to include("pull_requests_opened" => 150, "issues_opened" => 150)
  end

  it "follows advisory cursor pagination" do
    url = "https://api.github.com/repos/Homebrew/brew/security-advisories?state=published&per_page=100"
    next_url = "https://api.github.com/repositories/53238813/security-advisories?state=published&after=cursor"
    allow(GitHub::API).to receive(:open_rest).with(url, return_headers: true)
                                             .and_return([[{ "published_at" => "2025-01-01" }],
                                                          "Link: <#{next_url}>; rel=\"next\""])
    allow(GitHub::API).to receive(:open_rest).with(next_url, return_headers: true)
                                             .and_return([[{ "published_at" => "2026-01-01" }], ""])

    expect(described_class.new.repository_advisories("Homebrew/brew")).to eq(%w[2025-01-01 2026-01-01])
  end

  it "rejects advisory refreshes without changing the cache when the GitHub API is disabled" do
    cache = HOMEBREW_CACHE/"analytics/github/Homebrew/brew/advisories.json"
    cache.dirname.mkpath
    cache.write(JSON.generate({ fetched_at: "2025-01-01T00:00:00Z", dates: ["2024-12-31"] }))
    ENV["HOMEBREW_NO_GITHUB_API"] = "1"

    expect { described_class.new.repository_advisories("Homebrew/brew") }
      .to raise_error(RuntimeError, /require the GitHub API/)
    expect(JSON.parse(cache.read)).to eq("fetched_at" => "2025-01-01T00:00:00Z", "dates" => ["2024-12-31"])
  end

  it "can read today's advisory cache when the GitHub API is disabled" do
    cache = HOMEBREW_CACHE/"analytics/github/Homebrew/brew/advisories.json"
    cache.dirname.mkpath
    cache.write(JSON.generate({ fetched_at: Time.now.utc.iso8601, dates: ["2024-12-31"] }))
    ENV["HOMEBREW_NO_GITHUB_API"] = "1"

    expect(described_class.new.repository_advisories("Homebrew/brew")).to eq(["2024-12-31"])
  end

  it "does not advance activity caches when the GitHub API is disabled" do
    cache = HOMEBREW_CACHE/"analytics/github/Homebrew/brew/2026-01-01-2026-10-23.json"
    cache.dirname.mkpath
    cache.write(JSON.generate({ "pull_requests_opened" => 100, "issues_opened" => 20,
                                "github_fetched_at" => "2026-10-23T02:00:00Z" }))
    ENV["HOMEBREW_NO_GITHUB_API"] = "1"

    expect { described_class.new.github_activity("Homebrew/brew", from: "2026-01-01", to: "2026-10-24") }
      .to raise_error(RuntimeError, /require the GitHub API/)
    expect(cache.dirname.children).to eq([cache])
  end

  it "publishes current totals and annual advisory counts with exclusive end dates" do
    command = described_class.new
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 23))
    allow(Utils::Analytics::Repository).to receive(:new).and_return(
      instance_double(Utils::Analytics::Repository,
                      rows: [{ "period" => "current", "pull_requests_merged" => 7 },
                             { "period" => "2025", "pull_requests_merged" => 3 }], author_identities: {}),
    )
    allow(command).to receive_messages(github_activity:       { "pull_requests_merged" => 0 },
                                       repository_advisories: %w[2024-12-31
                                                                 2025-01-01 2025-12-31 2026-01-01])
    mktmpdir.cd do
      command.generate_repositories(repositories: { "Homebrew/brew" => Pathname.pwd })

      expect(JSON.parse(Pathname("_data/analytics/github/history.json").read).dig("repositories", "Homebrew/brew",
                                                                                  "rows"))
        .to eq([
          { "period" => "current", "pull_requests_opened" => 0, "issues_opened" => 0,
            "security_advisories" => 2, "security_disclosures" => 0, "pull_requests_merged" => 3,
            "start_date" => "2009-01-01", "end_date" => "2026-10-23" },
          { "period" => "2025", "security_advisories" => 2, "security_disclosures" => 0, "pull_requests_merged" => 3,
            "start_date" => "2025-01-01", "end_date" => "2026-01-01" },
        ])
    end
  end

  it "adds catalogue totals only when the formula backfill is complete" do
    command = described_class.new
    allow(Utils::Analytics::Repository).to receive(:new).and_return(
      instance_double(Utils::Analytics::Repository, rows: [{ "period" => "current", "formulae" => 7 }]),
    )
    mktmpdir.cd do
      totals = [true, false].map do |complete|
        allow(Utils::Analytics::FormulaHistory).to receive(:new).and_return(
          instance_double(Utils::Analytics::FormulaHistory,
                          report: { "complete" => complete, "rows" => [{ "period" => "current" }] }),
        )
        command.generate_formula_history
        JSON.parse(Pathname("_data/analytics/formula-history/history.json").read).dig("rows", 0, "formulae")
      end

      expect(totals).to eq([7, nil])
    end
  end

  it "includes the supplied legacy repository as a separate source" do
    command = described_class.new(legacy_homebrew: mktmpdir.to_s)
    allow(Utils::Analytics::Repository).to receive(:new).and_return(
      instance_double(Utils::Analytics::Repository, rows: [{ "period" => "current", "contributors" => 42 },
                                                           { "period" => "2015", "contributors" => 2 }]),
    )
    allow(command).to receive_messages(github_activity: { "pull_requests_opened" => 123 }, repository_advisories: [])
    mktmpdir.cd do
      command.generate_repositories(repositories: {})

      expect(JSON.parse(Pathname("_data/analytics/github/history.json").read).fetch("repositories"))
        .to match("Homebrew/legacy-homebrew" => {
          "source" => "https://github.com/Homebrew/legacy-homebrew",
          "rows"   => [include("contributors" => 42, "pull_requests_opened" => 123),
                       include("period" => "2015", "pull_requests_opened" => 123)],
        })
    end
  end

  it "uses frozen years and sums current counts without all-time searches" do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24))
    allow(Utils::Analytics::Repository).to receive(:new).and_return(
      instance_double(Utils::Analytics::Repository,
                      rows:              [{ "period" => "current", "pull_requests_merged" => 999 },
                                          { "period" => "2026", "pull_requests_merged" => 9 },
                                          { "period" => "2025", "pull_requests_merged" => 990 }],
                      author_identities: {}),
    )
    mktmpdir.cd do
      Pathname("history.json").write(JSON.generate({
        github: { through_year: 2025, repositories: { "Homebrew/brew" => {
          rows: [{ period: "current", pull_requests_opened: 999 },
                 { period: "2026", pull_requests_opened: 999 },
                 { period: "2025", pull_requests_opened: 100, pull_requests_merged: 80,
                   issues_opened: 20, security_advisories: 2 }],
        } } },
      }))
      command = described_class.new(history: "history.json")
      allow(command).to receive(:repository_advisories).and_return([])
      allow(command).to receive(:github_activity).and_raise("Unexpected historical or all-time search")
      allow(command).to receive(:github_activity).with("Homebrew/brew", from: "2026-01-01", to: "2026-10-24")
                                                 .and_return({ "pull_requests_opened" => 10, "issues_opened" => 3 })
      command.generate_repositories(repositories: { "Homebrew/brew" => Pathname.pwd })

      expect(JSON.parse(Pathname("_data/analytics/github/history.json").read)
                 .dig("repositories", "Homebrew/brew", "rows"))
        .to match([include("period" => "current", "pull_requests_opened" => 110, "pull_requests_merged" => 89,
                           "issues_opened" => 23, "security_advisories" => 2),
                   include("period" => "2026", "pull_requests_opened" => 10, "pull_requests_merged" => 9),
                   include("period" => "2025", "pull_requests_opened" => 100, "pull_requests_merged" => 80)])
    end
  end

  it "rejects an archive that freezes the current year" do
    mktmpdir.cd do
      Pathname("history.json").write(JSON.generate({ github: { through_year: Time.now.utc.year } }))

      expect { described_class.new(history: "history.json").archived_report("github") }
        .to raise_error(UsageError, /exclude the current and future years/)
    end
  end

  it "sums corrected frozen formula counts into the current row" do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24))
    allow(Utils::Analytics::FormulaHistory).to receive(:new).and_return(
      instance_double(Utils::Analytics::FormulaHistory, report: {
        "complete" => true, "rows" => [{ "period" => "current", "versions" => 999 },
                                       { "period" => "2026", "versions" => 20 },
                                       { "period" => "2025", "versions" => 979 }]
      }),
    )
    allow(Utils::Analytics::Repository).to receive(:new).and_return(
      instance_double(Utils::Analytics::Repository, rows: []),
    )
    mktmpdir.cd do
      Pathname("history.json").write(JSON.generate({ "formula-history" => {
        through_year: 2025, start_year: 2021,
        rows: [{ period: "current", versions: 999 }, { period: "2026", versions: 999 },
               { period: "2025", versions: 10 }],
        historical_backfill: { method: "Reconstructed formula metadata" }
      } }))
      described_class.new(history: "history.json").generate_formula_history

      expect(JSON.parse(Pathname("_data/analytics/formula-history/history.json").read))
        .to include("rows"                => [include("period" => "current", "versions" => 30),
                                              include("period" => "2026", "versions" => 20),
                                              include("period" => "2025", "versions" => 10)],
                    "historical_backfill" => { "method" => "Reconstructed formula metadata" })
    end
  end

  it "uses archived release rows only through the completed-year cutoff" do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24))
    allow(Utils::Analytics::Releases).to receive(:new).and_return(
      instance_double(Utils::Analytics::Releases, report: {
        "years"      => [{ "period" => "current", "releases" => 2 }, { "period" => "2026", "releases" => 1 },
                         { "period" => "2025", "releases" => 1 }],
        "releases"   => [{ "version" => "6.0.0", "date" => "2026-01-01", "commits" => 20 },
                         { "version" => "5.0.0", "date" => "2025-01-01", "commits" => 10 }],
        "aggregates" => [{ "version" => "6.0.0", "date" => "2026-01-01", "commits" => 30 },
                         { "version" => "5.0.0", "date" => "2025-01-01", "commits" => 15 }],
      }),
    )
    mktmpdir.cd do
      Pathname("history.json").write(JSON.generate({ releases: {
        through_year: 2025,
        years:        [{ period: "current", releases: 999 }, { period: "2026", releases: 999 },
                       { period: "2025", releases: 1 }],
        releases:     [{ version: "6.0.0", date: "2026-01-01", commits: 999 },
                       { version: "5.0.0", date: "2025-01-01", commits: 11 }],
        aggregates:   [{ version: "6.0.0", date: "2026-01-01", commits: 999 },
                       { version: "5.0.0", date: "2025-01-01", commits: 16 }],
      } }))
      described_class.new(history: "history.json").generate_releases

      expect(JSON.parse(Pathname("_data/analytics/releases/history.json").read))
        .to eq("years"      => [{ "period" => "current", "releases" => 2 }, { "period" => "2026", "releases" => 1 },
                                { "period" => "2025", "releases" => 1 }],
               "releases"   => [{ "version" => "6.0.0", "date" => "2026-01-01", "commits" => 20 },
                                { "version" => "5.0.0", "date" => "2025-01-01", "commits" => 11 }],
               "aggregates" => [{ "version" => "6.0.0", "date" => "2026-01-01", "commits" => 30 },
                                { "version" => "5.0.0", "date" => "2025-01-01", "commits" => 16 }])
    end
  end

  it "keeps the archived formula baseline when reconstructing a lost checkpoint" do
    history = instance_double(Utils::Analytics::FormulaHistory)
    allow(Utils::Analytics::FormulaHistory).to receive(:new).and_return(history)
    allow(Utils::Analytics::Repository).to receive(:new).and_return(
      instance_double(Utils::Analytics::Repository, rows: []),
    )
    mktmpdir.cd do
      Pathname("history.json").write(JSON.generate({ "formula-history" => {
        through_year: Time.now.utc.year - 1, start_year: 2021, rows: []
      } }))
      expect(history).to receive(:report).with(start_year: 2021).and_return({ "complete" => false, "rows" => [] })

      described_class.new(history: "history.json").generate_formula_history
    end
  end

  it "deduplicates contributors across the three primary repositories and years" do
    command = described_class.new
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 23))
    repositories = {
      "Homebrew/brew"            => { "2025" => %w[a b], "2026" => %w[a] },
      "Homebrew/homebrew-core"   => { "2025" => %w[b c], "2026" => %w[c] },
      "Homebrew/homebrew-cask"   => { "2025" => %w[a c], "2026" => %w[d] },
      "Homebrew/legacy-homebrew" => { "2025" => %w[legacy-only] },
    }.to_h do |name, authors|
      allow(Utils::Analytics::Repository).to receive(:new).with(Pathname(name), name).and_return(
        instance_double(Utils::Analytics::Repository, rows: [], author_identities: authors),
      )
      [name, Pathname(name)]
    end
    allow(command).to receive(:repository_advisories).and_return([])
    mktmpdir.cd do
      command.generate_repositories(repositories:)

      expect(JSON.parse(Pathname("_data/analytics/github/history.json").read).dig("combined_contributors", "rows"))
        .to include({ "period" => "current", "contributors" => 4, "new_contributors" => 4 },
                    { "period" => "2025", "contributors" => 3, "new_contributors" => 3 },
                    { "period" => "2026", "contributors" => 3, "new_contributors" => 1 })
    end
  end

  it "uses archived combined contributors only through the completed-year cutoff" do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 23))
    allow(Utils::Analytics::Repository).to receive(:new).and_return(
      instance_double(Utils::Analytics::Repository,
                      rows: [], author_identities: { "2024" => ["a"], "2025" => ["b"], "2026" => ["c"] }),
    )
    mktmpdir.cd do
      Pathname("history.json").write(JSON.generate({
        github: { through_year: 2024, combined_contributors: {
          rows: %w[current 2026 2025 2024].map do |period|
            { period:, contributors: 99, new_contributors: 99 }
          end,
        } },
      }))
      command = described_class.new(history: "history.json")
      allow(command).to receive(:repository_advisories).and_return([])
      command.generate_repositories(repositories: { "Homebrew/brew" => Pathname.pwd })

      expect(JSON.parse(Pathname("_data/analytics/github/history.json").read)
                 .dig("combined_contributors", "rows")
                 .first(4))
        .to eq([{ "period" => "current", "contributors" => 3, "new_contributors" => 3 },
                { "period" => "2026", "contributors" => 1, "new_contributors" => 1 },
                { "period" => "2025", "contributors" => 1, "new_contributors" => 1 },
                { "period" => "2024", "contributors" => 99, "new_contributors" => 99 }])
    end
  end
end
