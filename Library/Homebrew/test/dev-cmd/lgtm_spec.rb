# typed: true
# frozen_string_literal: true

require "open3"

require "cmd/shared_examples/args_parse"
require "dev-cmd/lgtm"
require "utils/tty"

RSpec.describe Homebrew::DevCmd::Lgtm do
  let(:klass) { Homebrew::DevCmd::Lgtm }

  it_behaves_like "parseable arguments"

  describe "#run" do
    subject(:lgtm) { klass.new(args) }

    let(:args) { [] }

    before do
      allow(Homebrew).to receive(:install_bundler_gems!)
      allow(lgtm).to receive(:ohai)
      allow(lgtm).to receive(:puts)
      allow(Utils).to receive(:popen_read).with("git", "ls-files", "--others", "--exclude-standard", "--full-name")
                                          .and_return("")
    end

    context "when run inside homebrew/core" do
      let(:tap) { instance_double(Tap, name: "homebrew/core") }
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
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "typecheck", "homebrew/core").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "style", "--changed", "--fix").ordered
        expect(lgtm).to receive(:opoo)
          .with("New formulae or casks were detected. Run `brew lgtm --online` to include `brew audit --new` checks.")
          .ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "audit", "--strict",
                                                   "--skip-style", "--formula", "homebrew/core/testball").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "audit", "--strict",
                                                   "--skip-style", "--formula", "homebrew/core/newball").ordered
        expect(lgtm).to receive(:opoo)
          .with("Skipping `brew test homebrew/core/newball`; the latest version is not installed.")
          .ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "test", "homebrew/core/testball").ordered

        lgtm.run
      end
    end

    context "when run inside homebrew/core with --online" do
      let(:args) { ["--online"] }
      let(:tap) { instance_double(Tap, name: "homebrew/core") }
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
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "typecheck", "homebrew/core").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "style", "--changed", "--fix").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "audit", "--strict", "--online",
                                                   "--skip-style", "--formula", "homebrew/core/testball").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "audit", "--new",
                                                   "--skip-style", "--formula", "homebrew/core/newball").ordered
        expect(lgtm).to receive(:opoo)
          .with("Skipping `brew test homebrew/core/newball`; the latest version is not installed.")
          .ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "test", "homebrew/core/testball").ordered

        lgtm.run
      end
    end

    context "when run inside homebrew/cask" do
      let(:tap) { instance_double(Tap, name: "homebrew/cask") }

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
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "typecheck", "homebrew/cask").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "style", "--changed", "--fix").ordered
        expect(lgtm).to receive(:opoo)
          .with("New formulae or casks were detected. Run `brew lgtm --online` to include `brew audit --new` checks.")
          .ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "audit", "--strict",
                                                   "--skip-style", "--cask", "homebrew/cask/test-cask").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "audit", "--strict",
                                                   "--skip-style", "--cask", "homebrew/cask/new-cask").ordered

        lgtm.run
      end
    end

    context "when run inside homebrew/cask with --online" do
      let(:args) { ["--online"] }
      let(:tap) { instance_double(Tap, name: "homebrew/cask") }

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
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "typecheck", "homebrew/cask").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "style", "--changed", "--fix").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "audit", "--strict", "--online",
                                                   "--skip-style", "--cask", "homebrew/cask/test-cask").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "audit", "--new",
                                                   "--skip-style", "--cask", "homebrew/cask/new-cask").ordered

        lgtm.run
      end
    end

    context "when untracked formulae or casks exist" do
      let(:tap) { instance_double(Tap, name: "homebrew/core") }

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
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "typecheck", "homebrew/core").ordered
        expect(lgtm).to receive(:safe_system).with(HOMEBREW_BREW_FILE, "style", "--changed", "--fix").ordered
        expect(lgtm).to receive(:opoo)
          .with("Untracked formula or cask files are not checked by `brew lgtm`; stage or commit them first.")
          .ordered

        lgtm.run
      end
    end
  end

  describe "cache fallback" do
    let(:repository_root) { Pathname(T.must(__dir__)).parent.parent.parent.parent }
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
        expect(stderr).to match(/developer command/)
      end
    end
  end
end
