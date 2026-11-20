# typed: true
# frozen_string_literal: true

require "utils/analytics/releases"

RSpec.describe Utils::Analytics::Releases do
  let(:repository) { mktmpdir }
  let(:git) do
    ["git", "-C", repository.to_s, "-c", "user.name=Test", "-c", "user.email=test@example.test",
     "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"]
  end

  before do
    Utils.safe_popen_read(*git, "init", "--quiet")
    commit("Initial", "2024-01-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "1.0.0")
    commit("Feature (#123)", "2025-01-01T12:00:00Z")
    commit("Merge pull request #123 from example/feature", "2025-01-02T12:00:00Z")
    commit("Fixes #456", "2025-01-03T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "-a", "1.1.0", "-m", "Release")
  end

  def commit(subject, date)
    ENV["GIT_AUTHOR_DATE"] = ENV["GIT_COMMITTER_DATE"] = date
    Utils.safe_popen_read(*git, "commit", "--allow-empty", "--quiet", "-m", subject)
  end

  it "counts releases, commit authors and distinct PR references without issue references" do
    expect(described_class.new(repository).report).to include(
      "years"    => include({ "period" => "2025", "releases" => 1 }),
      "releases" => include(include("version" => "1.1.0", "previous_version" => "1.0.0",
                                    "date" => "2025-01-03", "commits" => 3,
                                    "pull_requests" => 1, "contributors" => 1)),
    )
  end

  it "reuses release statistics when tags and the mailmap are unchanged" do
    report = described_class.new(repository)
    report.report
    allow(report).to receive(:git).and_call_original
    expect(report).not_to receive(:git).with("log", any_args)

    report.report
  end

  it "includes the root commit in the first release" do
    expect(described_class.new(repository).report.fetch("releases"))
      .to include(include("version" => "1.0.0", "commits" => 1, "contributors" => 1))
  end

  it "uses the preceding tag on the release branch for backports" do
    Utils.safe_popen_read(*git, "checkout", "--quiet", "-b", "backport", "1.0.0")
    commit("Backport (#789)", "2025-02-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "1.0.1")
    Utils.safe_popen_read(*git, "merge", "--quiet", "--no-edit", "1.1.0")

    expect(described_class.new(repository).report.fetch("releases"))
      .to include(include("version" => "1.0.1", "previous_version" => "1.0.0",
                          "commits" => 1, "pull_requests" => 1))
  end

  it "only reads new release ranges when a tag is added" do
    report = described_class.new(repository)
    report.report
    previous = Utils.safe_popen_read(*git, "rev-parse", "HEAD").strip
    commit("Next release (#789)", "2025-02-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "1.2.0")
    revision = Utils.safe_popen_read(*git, "rev-parse", "HEAD").strip
    allow(report).to receive(:git).and_call_original
    expect(report).not_to receive(:git).with("log", "--format=%P%x09%aE%x09%s", "1.0.0..1.1.0")
    expect(report).to receive(:git).with("log", "--format=%P%x09%aE%x09%s", "#{previous}..#{revision}")
                                   .at_least(:once)
                                   .and_call_original

    report.report
  end

  it "applies the current mailmap and excludes co-author trailers" do
    ENV["GIT_AUTHOR_EMAIL"] = "alias@example.test"
    commit("Feature (#789)\n\nCo-authored-by: Other <other@example.test>", "2025-02-01T12:00:00Z")
    (repository/".mailmap").write("Test <test@example.test> <alias@example.test>\n")
    Utils.safe_popen_read(*git, "add", ".mailmap")
    ENV.delete("GIT_AUTHOR_EMAIL")
    commit("Mailmap", "2025-02-02T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "1.2.0")

    expect(described_class.new(repository).report.fetch("releases"))
      .to include(include("version" => "1.2.0", "contributors" => 1))
  end

  it "counts contributors new to stable releases only once" do
    ENV["GIT_AUTHOR_EMAIL"] = "new@example.test"
    commit("New contributor (#789)", "2025-02-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "1.2.0")
    commit("Returning contributor (#790)", "2025-03-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "1.3.0")

    expect(described_class.new(repository).report.fetch("releases"))
      .to include(include("version" => "1.0.0", "new_contributors" => 1),
                  include("version" => "1.2.0", "new_contributors" => 1),
                  include("version" => "1.3.0", "new_contributors" => 0))
  end

  it "adds a major boundary range without double-counting release totals" do
    ENV["GIT_AUTHOR_EMAIL"] = "new@example.test"
    commit("Next major (#789)", "2026-01-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "2.0.0")

    expect(described_class.new(repository).report).to include(
      "totals"     => include("commits" => 5, "pull_requests" => 2, "contributors" => 2),
      "aggregates" => include(include("version" => "2.0.0", "kind" => "major",
                                      "previous_version" => "1.0.0", "commits" => 4,
                                      "contributors" => 2, "new_contributors" => 1)),
    )
  end

  it "selects the preceding version boundary even when an older series is tagged later" do
    commit("Major", "2025-02-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "2.0.0")
    commit("Older series", "2026-01-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "1.2.0")
    commit("Minor", "2026-02-01T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "2.1.0")

    expect(described_class.new(repository).report.fetch("aggregates"))
      .to include(include("version" => "2.1.0", "previous_version" => "2.0.0"))
  end
end
