# typed: true
# frozen_string_literal: true

require "open3"

require "cmd/shared_examples/args_parse"
require "dev-cmd/lgtm"
require "utils/tty"

RSpec.describe Homebrew::DevCmd::Lgtm do
  it_behaves_like "parseable arguments"
  it_behaves_like "a documented command", "lgtm"

  describe "#run" do
    subject(:lgtm) { described_class.new(args) }

    let(:args) { [] }
    let(:diagnostic_checks) { instance_double(Homebrew::Diagnostic::Checks, examine_git_origin: nil) }

    before do
      allow(Utils::GemSetup).to receive(:install_bundler_gems!)
      allow(lgtm).to receive(:ohai)
      allow(lgtm).to receive(:puts)
      allow(Homebrew::Diagnostic::Checks).to receive(:new).and_return(diagnostic_checks)
      allow(Utils).to receive(:popen_read).with("git", "ls-files", "--others", "--exclude-standard", "--full-name")
                                          .and_return("")
    end

    context "when run inside homebrew/core" do
      let(:tap) do
        instance_double(Tap, name: "homebrew/core", core_tap?: true, git_repository: nil)
      end
      let(:changed_formula) { instance_double(Formula, latest_version_installed?: true) }
      let(:new_formula) { instance_double(Formula, latest_version_installed?: false) }

      before do
        allow(Tap).to receive(:from_path).and_return(tap)
        allow(tap).to receive(:formula_file?) { |file| file.start_with?("Formula/") }
        allow(tap).to receive(:cask_file?).and_return(false)
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=AMR", "main")
                                            .and_return("Formula/testball.rb\nFormula/newball.rb\n")
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=A", "main")
                                            .and_return("Formula/newball.rb\n")
        allow(Formulary).to receive(:factory).with("homebrew/core/testball").and_return(changed_formula)
        allow(Formulary).to receive(:factory).with("homebrew/core/newball").and_return(new_formula)
      end

      it "audits formulae without online checks by default and skips tests for uninstalled formulae" do
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["typecheck", "homebrew/core"])
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["style", "--changed", "--fix"])
          .ordered
        expect(lgtm).to receive(:opoo)
          .with("New formulae or casks were detected. Run `brew lgtm --online` to include `brew audit --new` checks.")
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["audit", "--strict",
                                           "--skip-style", "--formula", "homebrew/core/testball"]).ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["audit", "--strict",
                                           "--skip-style", "--formula", "homebrew/core/newball"]).ordered
        expect(lgtm).to receive(:opoo)
          .with("Skipping `brew test homebrew/core/newball`; the latest version is not installed.")
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["test",
                                           "homebrew/core/testball"]).ordered

        lgtm.run
      end

      it "warns about a non-standard git origin" do
        allow(diagnostic_checks).to receive(:examine_git_origin)
          .and_return(Homebrew::Diagnostic::Finding.new("The current git origin is wrong."))
        allow(SystemCommand).to receive(:safe_system)
        allow(lgtm).to receive(:opoo)
        expect(lgtm).to receive(:opoo).with("The current git origin is wrong.")

        lgtm.run
      end

      it "checks the git origin against `$HOMEBREW_CORE_GIT_REMOTE`" do
        ENV["HOMEBREW_CORE_GIT_REMOTE"] = "https://mirror.example/homebrew-core.git"
        allow(SystemCommand).to receive(:safe_system)
        allow(lgtm).to receive(:opoo)
        expect(diagnostic_checks).to receive(:examine_git_origin)
          .with(nil, "https://mirror.example/homebrew-core.git")

        lgtm.run
      end
    end

    context "when run inside homebrew/core with --online" do
      let(:args) { ["--online"] }
      let(:tap) do
        instance_double(Tap, name: "homebrew/core", core_tap?: true, git_repository: nil)
      end
      let(:changed_formula) { instance_double(Formula, latest_version_installed?: true) }
      let(:new_formula) { instance_double(Formula, latest_version_installed?: false) }

      before do
        allow(Tap).to receive(:from_path).and_return(tap)
        allow(tap).to receive(:formula_file?) { |file| file.start_with?("Formula/") }
        allow(tap).to receive(:cask_file?).and_return(false)
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=AMR", "main")
                                            .and_return("Formula/testball.rb\nFormula/newball.rb\n")
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=A", "main")
                                            .and_return("Formula/newball.rb\n")
        allow(Formulary).to receive(:factory).with("homebrew/core/testball").and_return(changed_formula)
        allow(Formulary).to receive(:factory).with("homebrew/core/newball").and_return(new_formula)
      end

      it "audits changed formulae with --online and new formulae with --new" do
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["typecheck", "homebrew/core"])
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["style", "--changed", "--fix"])
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["audit", "--strict", "--online",
                                           "--skip-style", "--formula", "homebrew/core/testball"]).ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["audit", "--new",
                                           "--skip-style", "--formula", "homebrew/core/newball"]).ordered
        expect(lgtm).to receive(:opoo)
          .with("Skipping `brew test homebrew/core/newball`; the latest version is not installed.")
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["test",
                                           "homebrew/core/testball"]).ordered

        lgtm.run
      end
    end

    context "when run inside homebrew/cask" do
      let(:tap) do
        instance_double(Tap, name: "homebrew/cask", core_tap?: false, official?: true, git_repository: nil,
default_remote: nil)
      end

      before do
        allow(Tap).to receive(:from_path).and_return(tap)
        allow(tap).to receive(:formula_file?).and_return(false)
        allow(tap).to receive(:cask_file?) { |file| file.start_with?("Casks/") }
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=AMR", "main")
                                            .and_return("Casks/test-cask.rb\nCasks/new-cask.rb\n")
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=A", "main")
                                            .and_return("Casks/new-cask.rb\n")
      end

      it "audits casks without online checks by default" do
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["typecheck", "homebrew/cask"])
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["style", "--changed", "--fix"])
          .ordered
        expect(lgtm).to receive(:opoo)
          .with("New formulae or casks were detected. Run `brew lgtm --online` to include `brew audit --new` checks.")
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["audit", "--strict",
                                           "--skip-style", "--cask", "homebrew/cask/test-cask"]).ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["audit", "--strict",
                                           "--skip-style", "--cask", "homebrew/cask/new-cask"]).ordered

        lgtm.run
      end
    end

    context "when run inside homebrew/cask with --online" do
      let(:args) { ["--online"] }
      let(:tap) do
        instance_double(Tap, name: "homebrew/cask", core_tap?: false, official?: true, git_repository: nil,
default_remote: nil)
      end

      before do
        allow(Tap).to receive(:from_path).and_return(tap)
        allow(tap).to receive(:formula_file?).and_return(false)
        allow(tap).to receive(:cask_file?) { |file| file.start_with?("Casks/") }
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=AMR", "main")
                                            .and_return("Casks/test-cask.rb\nCasks/new-cask.rb\n")
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=A", "main")
                                            .and_return("Casks/new-cask.rb\n")
      end

      it "audits changed casks with --online and new casks with --new" do
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["typecheck", "homebrew/cask"])
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["style", "--changed", "--fix"])
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["audit", "--strict", "--online",
                                           "--skip-style", "--cask", "homebrew/cask/test-cask"]).ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["audit", "--new",
                                           "--skip-style", "--cask", "homebrew/cask/new-cask"]).ordered

        lgtm.run
      end
    end

    context "when untracked formulae or casks exist" do
      let(:tap) do
        instance_double(Tap, name: "homebrew/core", core_tap?: true, git_repository: nil)
      end

      before do
        allow(Tap).to receive(:from_path).and_return(tap)
        allow(tap).to receive(:formula_file?) { |file| file.start_with?("Formula/") }
        allow(tap).to receive(:cask_file?) { |file| file.start_with?("Casks/") }
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=AMR", "main")
                                            .and_return("")
        allow(Utils).to receive(:popen_read).with("git", "diff", "--name-only", "--no-relative",
                                                  "--diff-filter=A", "main")
                                            .and_return("")
        allow(Utils).to receive(:popen_read).with("git", "ls-files", "--others", "--exclude-standard", "--full-name")
                                            .and_return("Formula/newball.rb\n")
      end

      it "warns that untracked formulae and casks are skipped" do
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["typecheck", "homebrew/core"])
          .ordered
        expect(SystemCommand)
          .to receive(:safe_system)
          .with(HOMEBREW_BREW_FILE, args: ["style", "--changed", "--fix"])
          .ordered
        expect(lgtm).to receive(:opoo)
          .with("Untracked formula or cask files are not checked by `brew lgtm`; stage or commit them first.")
          .ordered

        lgtm.run
      end
    end
  end

  describe "cache fallback" do
    let(:repository_root) { HOMEBREW_LIBRARY_PATH.parent.parent }
    let(:test_root) do
      (repository_root/"tmp").mkpath
      Pathname(Dir.mktmpdir("brew-lgtm-cache-fallback-", repository_root/"tmp"))
    end
    let(:isolated_brew) { test_root/"prefix/bin/brew" }
    let(:read_only_cache) { test_root/"readonly-cache" }
    let(:fallback_cache) { test_root/"prefix/tmp/cache" }
    let(:cache_file) { read_only_cache/"api/cask_names.txt" }

    before do
      isolated_brew.dirname.mkpath
      FileUtils.cp repository_root/"bin/brew", isolated_brew
      isolated_brew.chmod(0755)
      FileUtils.ln_s repository_root/"Library", test_root/"prefix/Library"
      cache_file.dirname.mkpath
      cache_file.write("copied-from-cache\n")
      FileUtils.chmod("u-w", read_only_cache)
    end

    after do
      FileUtils.chmod("u+rwx", read_only_cache)
      FileUtils.rm_rf test_root
    end

    it "uses a repository-local cache when HOMEBREW_CACHE is not writable" do
      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(
          {
            "HOMEBREW_CACHE"              => read_only_cache.to_s,
            "HOMEBREW_INTEGRATION_TEST"   => "1",
            "HOMEBREW_USE_RUBY_FROM_PATH" => ENV.fetch("HOMEBREW_USE_RUBY_FROM_PATH", nil),
          },
          isolated_brew.to_s,
          "lgtm",
          "--help",
        )
      end

      expect(status.success?).to be true
      expect(Tty.strip_ansi(stdout)).to match(
        Regexp.new(
          "Run brew typecheck, brew style --changed and the relevant brew tests,\\s+" \
          "brew audit and brew test checks in one go\\.",
        ),
      )
      if stderr.include?("HOMEBREW_CACHE is not writable")
        expect(stderr).to match(
          %r{HOMEBREW_CACHE is not writable at .+; using .+/tmp/cache for Homebrew cache files instead\.},
        )
        expect(fallback_cache/"api/cask_names.txt").to be_a_file
        expect((fallback_cache/"api/cask_names.txt").read).to eq("copied-from-cache\n")
      elsif stderr.present?
        expect(stderr).to include("developer command")
      end
    end
  end
end
