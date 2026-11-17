# typed: true
# frozen_string_literal: true

require "utils/analytics/repository"

RSpec.describe Utils::Analytics::Repository do
  let(:repository) { mktmpdir }
  let(:git) do
    ["git", "-C", repository.to_s, "-c", "user.name=Test", "-c", "user.email=tést@example.test",
     "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null"]
  end

  before do
    ENV["GIT_AUTHOR_EMAIL"] = "tést@example.test"
    allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 23))
    Utils.safe_popen_read(*git, "init", "--quiet")
    (repository/"Formula").mkpath
    (repository/"Formula/one.rb").write("one")
    commit("2024-01-02T12:00:00Z")
    Utils.safe_popen_read(*git, "tag", "1.0.0")
    (repository/"Formula/two.rb").write("two")
    commit("2025-01-02T12:00:00Z")
    (repository/"Formula/one.rb").unlink
    (repository/"Formula/alias.rb").make_symlink("two.rb")
    commit("2026-01-02T12:00:00Z")
  end

  def commit(date)
    ENV["GIT_AUTHOR_DATE"] = ENV["GIT_COMMITTER_DATE"] = date
    Utils.safe_popen_read(*git, "add", ".")
    Utils.safe_popen_read(*git, "commit", "--quiet", "-m", "Update catalogue")
  end

  describe "#pull_request_numbers" do
    subject(:report) { described_class.new(repository, "Homebrew/brew") }

    it "combines merge, squash and closing references without duplicates" do
      message = <<~EOS
        Merge pull request #123 from user/branch (#456)

        Closes #123.
        Closes Homebrew/brew#789.
        Closes https://github.com/Homebrew/brew/pull/1011.
      EOS

      expect(report.pull_request_numbers(message)).to eq(%w[123 456 789 1011])
    end

    it "ignores references to other repositories and non-closing mentions" do
      message = <<~EOS
        Mention #123

        Closes Homebrew/homebrew-core#456.
        Closes https://github.com/Homebrew/homebrew-core/pull/789.
        Fixes #1011.
      EOS

      expect(report.pull_request_numbers(message)).to be_empty
    end

    it "matches closing references regardless of capitalisation" do
      expect(report.pull_request_numbers("closes HOMEBREW/BREW#123\nCLOSES #456")).to eq(%w[123 456])
    end

    it "only treats merge and squash references in the subject as pull requests" do
      expect(report.pull_request_numbers("Update formula\nMerge pull request #123\nDetails (#456)")).to be_empty
    end

    it "ignores legacy issues preceding the first pull request" do
      legacy = described_class.new(repository, "Homebrew/legacy-homebrew")

      expect(legacy.pull_request_numbers("Closes #2325.\nCloses #2326.")).to eq(["2326"])
    end
  end

  describe "#catalogue_count" do
    subject(:report) { described_class.new(repository, "Homebrew/homebrew-core") }

    before do
      entries = [
        "100644 blob abc\tFormula/one.rb",
        "100755 blob abc\tFormula/t/two.rb",
        "100644 blob abc\tLibrary/Formula/three.rb",
        "120000 blob abc\tFormula/alias.rb",
        "100644 blob abc\tFormula/README.md",
        "100644 blob abc\tFormula/too/deep/ignored.rb",
        "100644 blob abc\tCasks/one.rb",
        "100755 blob abc\tCasks/font/t/two.rb",
        "100644 blob abc\tCask/three.rb",
        "120000 blob abc\tCasks/alias.rb",
        "100644 blob abc\tCasks/README.md",
        "040000 tree abc\tFormula/subtree.rb",
      ]
      allow(report).to receive(:git).with("ls-tree", "-rz", "revision").and_return(entries.join("\0"))
    end

    it "counts regular formula files in current and historical layouts" do
      expect(report.catalogue_count("revision", formula_repository: true)).to eq(3)
    end

    it "counts nested casks but excludes aliases, directories and other files" do
      expect(report.catalogue_count("revision", formula_repository: false)).to eq(3)
    end

    it "handles an empty tree" do
      allow(report).to receive(:git).with("ls-tree", "-rz", "revision").and_return("")

      expect(report.catalogue_count("revision", formula_repository: true)).to eq(0)
    end
  end

  it "counts year-end catalogues including deleted formulae but excluding aliases" do
    expect(described_class.new(repository, "Homebrew/homebrew-core").rows.map do |row|
      [row["period"], row["formulae"]]
    end)
      .to include(["current", 1], ["2026", 1], ["2025", 2], ["2024", 1], ["2009", 0])
  end

  it "counts commit author identities and stable release tags separately" do
    rows = described_class.new(repository, "Homebrew/brew").rows

    expect(rows).to include(include("period" => "current", "contributors" => 1, "releases" => 1),
                            include("period" => "2025", "contributors" => 1, "releases" => 0))
  end

  it "reuses unchanged Git history from the checkpoint" do
    report = described_class.new(repository, "Homebrew/homebrew-core")
    report.rows
    allow(report).to receive(:git).and_call_original
    expect(report).not_to receive(:git).with("log", any_args)

    report.rows
  end

  it "updates the checkpoint using only newly reachable commits" do
    report = described_class.new(repository, "Homebrew/homebrew-core")
    report.rows
    previous = Utils.safe_popen_read(*git, "rev-parse", "HEAD").strip
    (repository/"Formula/three.rb").write("three")
    commit("2026-02-02T12:00:00Z")
    allow(report).to receive(:git).and_call_original
    expect(report).to receive(:git).with("log", "--no-merges", "--format=%ct%x09%aE", "#{previous}..HEAD")
                                   .and_call_original

    report.rows
  end

  it "includes casks in nested font directories" do
    path = repository/"Casks/font/font-a/font-alpha.rb"
    path.dirname.mkpath
    path.write("font")
    commit("2026-02-02T12:00:00Z")

    expect(described_class.new(repository, "Homebrew/homebrew-cask").rows.first).to include("casks" => 1)
  end

  it "persists distinct binary author identities" do
    report = described_class.new(repository, "Homebrew/brew")
    allow(report).to receive(:git).and_call_original
    allow(report).to receive(:git).with("log", "--no-merges", "--format=%ct%x09%aE", "HEAD")
                                  .and_return("1767225600\t\xFF@example.test\n1767225600\t\xFE@example.test".b)

    expect(report.rows.first).to include("contributors" => 2, "new_contributors" => 2)
  end

  it "counts both formulae and release tags in the legacy repository" do
    expect(described_class.new(repository, "Homebrew/legacy-homebrew").rows)
      .to include(include("period" => "current", "formulae" => 1, "releases" => 1),
                  include("period" => "2025", "formulae" => 2, "releases" => 0))
  end

  it "restores yearly author identities from an unchanged checkpoint" do
    described_class.new(repository, "Homebrew/brew").rows
    report = described_class.new(repository, "Homebrew/brew")
    report.rows

    expect(report.author_identities).to eq(
      "2024" => ["tést@example.test".unpack1("H*")],
      "2025" => ["tést@example.test".unpack1("H*")],
      "2026" => ["tést@example.test".unpack1("H*")],
    )
  end

  it "counts applied PRs once across pull, merge and squash commits" do
    Utils.safe_popen_read(*git, "commit", "--allow-empty", "--quiet", "-m",
                          "Apply formula\n\nCloses #123.\nCloses Homebrew/homebrew-core#456.\n" \
                          "Closes https://github.com/another/tap/pull/789.\nFixes #999.")
    Utils.safe_popen_read(*git, "commit", "--allow-empty", "--quiet", "-m", "Merge pull request #123 from test/pr")
    Utils.safe_popen_read(*git, "commit", "--allow-empty", "--quiet", "-m", "Update (#456)")

    expect(described_class.new(repository, "Homebrew/homebrew-core").rows.first)
      .to include("pull_requests_merged" => 2)
  end

  it "excludes legacy issue closures before numbered pull requests existed" do
    Utils.safe_popen_read(*git, "commit", "--allow-empty", "--quiet", "-m",
                          "Apply changes\n\nCloses #2325.\nCloses #2326.")

    expect(described_class.new(repository, "Homebrew/legacy-homebrew").rows.first)
      .to include("pull_requests_merged" => 1)
  end

  it "distinguishes new contributors from returning contributors" do
    rows = described_class.new(repository, "Homebrew/brew").rows

    expect(rows).to include(include("period" => "2024", "contributors" => 1, "new_contributors" => 1),
                            include("period" => "2025", "contributors" => 1, "new_contributors" => 0))
  end

  it "counts cask additions and removals without counting renames or aliases" do
    (repository/"Casks").mkpath
    (repository/"Casks/one.rb").write("one")
    commit("2025-03-01T12:00:00Z")
    (repository/"Casks/one.rb").rename(repository/"Casks/two.rb")
    (repository/"Casks/alias.rb").make_symlink("two.rb")
    commit("2025-04-01T12:00:00Z")
    (repository/"Casks/two.rb").unlink
    commit("2026-04-01T12:00:00Z")

    expect(described_class.new(repository, "Homebrew/homebrew-cask").rows)
      .to include(include("period" => "2025", "casks" => 1, "added" => 1, "removed" => 0),
                  include("period" => "2026", "casks" => 0, "added" => 0, "removed" => 1))
  end

  it "counts named current maintainers in the README without former maintainers or sponsors" do
    (repository/"README.md").write <<~MARKDOWN
      Homebrew's [Project Leader](https://docs.brew.sh/governance) is [One](https://github.com/one).

      Homebrew's maintainers are [One](https://github.com/One) and [Two](https://github.com/two).

      Former maintainers include [Three](https://github.com/three).

      Sponsors include [Four](https://github.com/four).
    MARKDOWN
    commit("2026-04-01T12:00:00Z")

    expect(described_class.new(repository, "Homebrew/brew").rows.first).to include("maintainers" => 2)
  end
end
