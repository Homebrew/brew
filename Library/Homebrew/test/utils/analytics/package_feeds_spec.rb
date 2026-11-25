# typed: true
# frozen_string_literal: true

require "dev-cmd/generate-cask-feeds"
require "dev-cmd/generate-formula-feeds"

RSpec.describe Utils::Analytics::PackageFeeds do
  let(:root) { mktmpdir }
  let(:repository) { root/"core" }
  let(:commit_dates) { (1..).lazy.map { |index| Time.utc(2026, 1, 1) + (60 * index) } }
  let(:feed_class) { Homebrew::DevCmd::GenerateFormulaFeeds::Feeds }

  before do
    repository.mkpath
    git("init", "--quiet", "--initial-branch=main")
    git("config", "user.name", "Feed tests")
    git("config", "user.email", "feeds@example.test")
    git("config", "commit.gpgsign", "false")
    git("config", "core.hooksPath", File::NULL)
    git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main")
  end

  def git(*args, path: repository)
    stdout, stderr, status = Open3.capture3("git", "-C", path.to_s, *args)
    raise stderr unless status.success?

    stdout.strip
  end

  def commit(message = "Change formula")
    git("add", ".")
    date = commit_dates.next.iso8601
    _stdout, stderr, status = Open3.capture3(
      { "GIT_AUTHOR_DATE" => date, "GIT_COMMITTER_DATE" => date },
      "git", "-C", repository.to_s, "commit", "--quiet", "-m", message
    )
    raise stderr unless status.success?

    git("update-ref", "refs/remotes/origin/main", "HEAD")
    git("rev-parse", "HEAD")
  end

  def formula(name = "example", version: "1.0", revision: 0, rebuild: 0, extra: "")
    path = repository/"Formula"/"#{name}.rb"
    path.dirname.mkpath
    class_name = name.split("-").map(&:capitalize).join
    path.write <<~RUBY
      class #{class_name} < Formula
        desc "Tools & utilities"
        homepage "https://example.test"
        url "https://example.test/#{name}-#{version}.tar.gz"
        version "#{version}"
        sha256 "#{"a" * 64}"
        license "MIT"
        revision #{revision}
        bottle do
          rebuild #{rebuild}
        end
        #{extra}
      end
    RUBY
    path
  end

  def feeds
    feed_class.new(repository).generate
  end

  it "reads the remote default branch instead of local commits" do
    formula
    commit
    formula(version: "2.0")
    upstream = commit
    git("switch", "--quiet", "-c", "local")
    formula(version: "3.0")
    commit
    git("update-ref", "refs/remotes/origin/main", upstream)

    expect(feeds).to include(
      "revision" => upstream,
      "new"      => [include("versions" => ["1.0"])],
      "updated"  => [include("versions" => ["2.0"])],
    )
  end

  it "uses merged changes once and excludes bottles, resources, aliases and renames" do
    path = formula
    added = commit
    git("switch", "--quiet", "-c", "release")
    formula(version: "1.1")
    commit
    formula(version: "1.2")
    commit
    git("switch", "--quiet", "main")
    git("merge", "--quiet", "--no-ff", "release", "-m", "Merge release")
    released = git("rev-parse", "HEAD")
    formula(version: "1.2", revision: 1)
    revised = commit
    formula(version: "1.2", revision: 1, rebuild: 1)
    commit
    formula(version: "1.2", revision: 1, rebuild: 1, extra: <<~RUBY)
      resource "helper" do
        url "https://example.test/helper-2.0.tar.gz"
        sha256 "#{"b" * 64}"
      end
    RUBY
    commit
    renamed_path = repository/"Formula/e/example.rb"
    renamed_path.dirname.mkpath
    FileUtils.mv(path, renamed_path)
    (repository/"Aliases").mkpath
    File.symlink("../Formula/e/example.rb", repository/"Aliases/alias")
    commit

    result = feeds
    expect(result.fetch("new").map { |entry| entry.fetch("commit") }).to eq([added])
    expect(result.fetch("updated").map { |entry| entry.fetch("commit") }).to eq([revised, released])
    expect(result.fetch("updated").map { |entry| entry.fetch("versions") }).to eq([["1.2_1"], ["1.2"]])
    expect(result.fetch("updated").first.fetch("date")).to eq((Time.utc(2026, 1, 1) + (4 * 60)).iso8601)
    expect(feeds).to eq(result)
  end

  it "counts a platform-specific version change once" do
    formula(extra: "on_linux do\n    version \"2.0\"\n  end")
    commit
    formula(extra: "on_linux do\n    version \"2.1\"\n  end")
    commit
    result = feeds
    expect(result.fetch("updated").length).to eq(1)
    expect(result.fetch("updated").first.fetch("versions")).to eq(["1.0", "2.1"])
  end

  def edited_move(version)
    path = formula(extra: (1..40).map { |index| "# Original source line #{index}" }.join("\n"))
    added = commit
    formula(version:, extra: (1..40).map { |index| "# Replacement source line #{index}" }.join("\n"))
    moved_path = repository/"Formula/e/example.rb"
    moved_path.dirname.mkpath
    FileUtils.mv(path, moved_path)
    moved = commit
    expect(git("diff", "HEAD^", "HEAD", "--name-status", "--find-renames=50%").lines.map(&:strip))
      .to contain_exactly("A\tFormula/e/example.rb", "D\tFormula/example.rb")
    [added, moved, feeds]
  end

  it "recognizes a heavily edited move without a version change" do
    added, _moved, result = edited_move("1.0")

    expect([result.fetch("new").map { |entry| entry.fetch("commit") }, result.fetch("updated")])
      .to eq([[added], []])
  end

  it "recognizes a version update during a heavily edited move" do
    added, moved, result = edited_move("2.0")

    expect([result.fetch("new").map { |entry| entry.fetch("commit") }, result.fetch("updated")])
      .to match([[added], [include("commit" => moved, "versions" => ["2.0"])]])
  end

  it "treats a formula reintroduced after a separate deletion as an addition" do
    path = formula
    added = commit
    path.unlink
    commit
    formula(version: "2.0")
    reintroduced = commit

    result = feeds
    expect(result.fetch("new").map { |entry| entry.fetch("commit") }).to eq([reintroduced, added])
    expect(result.fetch("updated")).to be_empty
  end

  it "validates each formula path even when source blobs are identical" do
    path = formula
    FileUtils.cp(path, repository/"Formula/zother.rb")
    commit
    expect { feeds }.to raise_error(%r{Cannot read formula metadata for Formula/zother.rb})
  end

  it "continues through history pages containing no formula changes" do
    stub_const("Utils::Analytics::PackageFeeds::BATCH_SIZE", 1)
    formula
    commit
    (repository/"README").write("docs")
    commit
    formula(version: "2.0")
    commit
    result = feeds
    expect(result.fetch("new").map { |entry| entry.fetch("versions") }).to eq([["1.0"]])
    expect(result.fetch("updated").map { |entry| entry.fetch("versions") }).to eq([["2.0"]])
  end

  it "caps the feeds at 50 additions and 500 updates even within a single commit" do
    501.times { |index| formula("package-#{index}") }
    commit
    501.times { |index| formula("package-#{index}", version: "2.0") }
    commit
    result = feeds
    expect(result.fetch("new").length).to eq(50)
    expect(result.fetch("updated").length).to eq(500)
    expect(result.fetch("updated").map { |entry| entry.fetch("id") }.uniq.length).to eq(500)

    formula("fresh")
    formula("package-0", version: "3.0")
    commit
    refreshed = feeds
    expect(refreshed.fetch("new").first.fetch("name")).to eq("fresh")
    expect(refreshed.fetch("updated").first.fetch("versions")).to eq(["3.0"])
    { "new" => 50, "updated" => 500 }.each do |type, limit|
      expect(refreshed.fetch(type).length).to eq(limit)
      previous_ids = result.fetch(type).map { |entry| entry.fetch("id") }
      refreshed_ids = refreshed.fetch(type).map { |entry| entry.fetch("id") }
      expect((previous_ids & refreshed_ids).length).to eq(limit - 1)
    end
  end

  it "fails when formula metadata cannot be read" do
    path = formula
    commit
    path.write("class Example < Formula\n  invalid_metadata!\nend\n")
    commit
    expect { feeds }.to raise_error(/Cannot read formula metadata/)
  end

  it "rejects a shallow checkout instead of treating its boundary as additions" do
    formula
    commit
    formula(version: "2.0")
    commit
    shallow = root/"shallow"
    git("clone", "--quiet", "--depth=1", "file://#{repository}", shallow.to_s)
    expect { feed_class.new(shallow).generate }.to raise_error(/unshallow/)
  end

  it "tracks updates from historical to nested formula directories" do
    path = formula
    historical = repository/"Library/Formula/example.rb"
    historical.dirname.mkpath
    FileUtils.mv(path, historical)
    commit
    path = formula(version: "2.0")
    historical.unlink
    nested = repository/"Formula/e/examples/example.rb"
    nested.dirname.mkpath
    FileUtils.mv(path, nested)
    commit

    expect(feeds).to include(
      "new" => [include("versions" => ["1.0"])], "updated" => [include("versions" => ["2.0"])],
    )
  end

  context "with casks" do
    let(:feed_class) { Homebrew::DevCmd::GenerateCaskFeeds::Feeds }

    def cask(version: "1.0", checksum: "a" * 64, extra: "")
      path = repository/"Casks/example.rb"
      path.dirname.mkpath
      path.write <<~RUBY
        cask "example" do
          version #{version.inspect}
          sha256 "#{checksum}"
          url "https://example.test/example.dmg"
          name "Example"
          desc "Example application"
          homepage "https://example.test"
          #{extra}
        end
      RUBY
      path
    end

    it "collects cask additions and updates while excluding checksum edits, moves and formulae" do
      formula
      path = cask
      added = commit
      cask(version: "2.0")
      updated = commit
      cask(version: "2.0", checksum: "b" * 64)
      commit
      moved = repository/"Casks/e/example.rb"
      moved.dirname.mkpath
      FileUtils.mv(path, moved)
      commit

      expect(feeds).to include(
        "new"     => [include("commit" => added, "name" => "example", "versions" => ["1.0"])],
        "updated" => [include("commit" => updated, "versions" => ["2.0"])],
      )
    end

    it "counts architecture-specific version changes once" do
      cask(extra: "on_intel do\n    version \"2.0\"\n  end")
      commit
      cask(extra: "on_intel do\n    version \"2.1\"\n  end")
      commit

      expect(feeds.fetch("updated")).to match([include("versions" => ["1.0", "2.1"])])
    end

    it "includes Linux-specific cask version changes" do
      cask(extra: "on_linux do\n    version \"2.0\"\n  end")
      commit
      cask(extra: "on_linux do\n    version \"2.1\"\n  end")
      commit

      expect(feeds.fetch("updated")).to match([include("versions" => ["1.0", "2.1"])])
    end

    it "includes cask releases on newly supported platforms" do
      cask(version: nil, extra: "on_macos do\n    version \"1.0\"\n  end")
      commit
      cask(version: nil, extra: <<~RUBY)
        on_macos do
          version "1.0"
        end
        on_linux do
          version "2.0"
        end
      RUBY
      updated = commit

      expect(feeds.fetch("updated")).to match([include("commit" => updated, "versions" => ["1.0", "2.0"])])
    end

    def single_os_feeds(os)
      path = cask(version: nil, extra: <<~RUBY)
        on_#{os} do
          version "1.0"
        end
        uninstall quit: "com.example.\#{version.major}"
      RUBY
      commit
      path.write(path.read.sub('version "1.0"', 'version "2.0"'))
      commit
      feeds
    end

    it "handles casks whose definitions only load on macOS" do
      expect(single_os_feeds("macos")).to include(
        "new" => [include("versions" => ["1.0"])], "updated" => [include("versions" => ["2.0"])],
      )
    end

    it "handles casks whose definitions only load on Linux" do
      expect(single_os_feeds("linux")).to include(
        "new" => [include("versions" => ["1.0"])], "updated" => [include("versions" => ["2.0"])],
      )
    end

    it "validates each cask token against its path" do
      path = cask
      FileUtils.cp(path, repository/"Casks/other.rb")
      commit

      expect { feeds }.to raise_error(%r{Cannot read cask metadata for Casks/other.rb})
    end

    it "keeps latest-version casks in additions without treating checksum edits as releases" do
      cask(version: :latest)
      commit
      cask(version: :latest, checksum: "b" * 64)
      commit

      expect(feeds).to include("new" => [include("versions" => ["latest"])], "updated" => [])
    end

    it "tracks updates from historical to current cask directories" do
      path = cask
      historical = repository/"Cask/example.rb"
      historical.dirname.mkpath
      FileUtils.mv(path, historical)
      commit
      cask(version: "2.0")
      historical.unlink
      commit

      expect(feeds).to include(
        "new" => [include("versions" => ["1.0"])], "updated" => [include("versions" => ["2.0"])],
      )
    end
  end
end
