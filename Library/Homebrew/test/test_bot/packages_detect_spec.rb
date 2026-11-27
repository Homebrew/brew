# typed: strict
# frozen_string_literal: true

require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::PackagesDetect do
  describe "::DEFAULT_TEST_FORMULAE" do
    it "uses GitHub-hosted, dependency-free formulae for default formula testing" do
      expect(Homebrew::TestBot::PackagesDetect::DEFAULT_TEST_FORMULAE).to eq(%w[termbox bats-core])
    end
  end

  it "reports changed formulae and casks with separate lists for additions and deletions" do
    tap = Tap.fetch("thirdparty/mixed")
    (tap.path/"Formula").mkpath
    (tap.cask_dir/"a").mkpath
    (tap.cask_dir/"removed.rb").write("# removed")
    (tap.cask_dir/"a/app.rb").write("# first")
    git = ["git", "-C", tap.path.to_s]
    Utils.safe_popen_read(*git, "init", "-b", "main")
    Utils.safe_popen_read(*git, "add", ".")
    Utils.safe_popen_read(*git, "commit", "-m", "Initial tap")
    Utils.safe_popen_read(*git, "remote", "add", "origin", tap.path.to_s)
    Utils.safe_popen_read(*git, "switch", "-c", "changes")
    (tap.cask_dir/"removed.rb").unlink
    (tap.cask_dir/"a/app.rb").append_lines("# changed")
    (tap.cask_dir/"new.rb").write("# new")
    (tap.path/"Formula/new.rb").write("# formula")
    Utils.safe_popen_read(*git, "add", "-A")
    Utils.safe_popen_read(*git, "commit", "-m", "Change both packages")

    ENV["GITHUB_REPOSITORY"] = tap.full_name
    ENV["GITHUB_BASE_REF"] = "main"
    ENV["GITHUB_REF"] = "refs/pull/1/merge"
    ENV["GITHUB_EVENT_NAME"] = "pull_request"
    ENV["GITHUB_SHA"] = Utils.safe_popen_read(*git, "rev-parse", "HEAD").chomp
    ENV["GITHUB_ACTIONS"] = "true"
    ENV["GITHUB_OUTPUT"] = (tap.path/"output").to_s

    mktmpdir do |workdir|
      workdir.cd do
        args = Homebrew::Cmd::TestBotCmd.new(["--only-packages-detect"]).args
        expect do
          expect(Homebrew::TestBot::TestRunner.run!(tap, git: "git", args:)).to be(true)
        end.to output(%r{deleted_casks +thirdparty/mixed/removed}).to_stdout
      end
    end

    expect((tap.path/"output").readlines(chomp: true)).to include(
      "testing_formulae=thirdparty/mixed/new",
      "testing_casks=thirdparty/mixed/new,thirdparty/mixed/app",
      "added_casks=thirdparty/mixed/new",
      "deleted_casks=thirdparty/mixed/removed",
    )
  ensure
    FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
  end

  it "detects merge-group changes from origin/main when origin/HEAD is missing" do
    mktmpdir do |path|
      tap = Tap.fetch("thirdparty/queued")
      allow(tap).to receive(:path).and_return(path)
      git = ["git", "-C", path.to_s]
      Utils.safe_popen_read(*git, "init", "-b", "main")
      Utils.safe_popen_read(*git, "commit", "--allow-empty", "-m", "Initial tap")
      Utils.safe_popen_read(*git, "update-ref", "refs/remotes/origin/main", "HEAD")
      tap.cask_dir.mkpath
      (tap.cask_dir/"queued.rb").write("# new cask")
      Utils.safe_popen_read(*git, "add", ".")
      Utils.safe_popen_read(*git, "commit", "-m", "Add queued cask")

      ENV["GITHUB_REPOSITORY"] = tap.full_name
      ENV["GITHUB_EVENT_NAME"] = "merge_group"
      ENV.delete("GITHUB_BASE_REF")
      ENV["GITHUB_REF"] = "refs/heads/gh-readonly-queue/main/pr-1"
      ENV["GITHUB_SHA"] = Utils.safe_popen_read(*git, "rev-parse", "HEAD").chomp
      ENV["GITHUB_OUTPUT"] = (path/"output").to_s
      detect = described_class.new("HEAD", tap:, git: "git", dry_run: false, fail_fast: false, verbose: false)
      args = Homebrew::Cmd::TestBotCmd.new(["--only-packages-detect"]).args

      detect.run!(args:)
      expect(detect.testing_casks).to eq(["thirdparty/queued/queued"])

      Utils.safe_popen_read(*git, "update-ref", "-d", "refs/remotes/origin/main")
      expect { detect.run!(args:) }.to raise_error(UsageError, %r{origin/main})
    end
  end

  it "accepts --only-formulae-detect as an alias for package detection" do
    expect(Homebrew::Cmd::TestBotCmd.new(["--only-formulae-detect"]).args.only_packages_detect?).to be(true)
  end

  it "detects casks in a local tap before it has an origin" do
    %w[CI GITHUB_ACTIONS GITHUB_REPOSITORY].each { |key| ENV.delete(key) }
    mktmpdir do |path|
      tap = Tap.fetch("thirdparty/local")
      allow(tap).to receive(:path).and_return(path)
      tap.cask_dir.mkpath
      (tap.cask_dir/"app.rb").write("# new cask")
      git = ["git", "-C", path.to_s]
      Utils.safe_popen_read(*git, "init")
      Utils.safe_popen_read(*git, "add", ".")
      Utils.safe_popen_read(*git, "commit", "-m", "Add a cask")

      detect = described_class.new("HEAD", tap:, git: "git", dry_run: false, fail_fast: false, verbose: false)
      detect.run!(args: Homebrew::Cmd::TestBotCmd.new(["--only-packages-detect"]).args)

      expect(detect.added_casks).to eq(["thirdparty/local/app"])
    end
  end
end
