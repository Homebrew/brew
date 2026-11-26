# typed: strict
# frozen_string_literal: true

require "bump"

RSpec.describe Homebrew::Bump do
  describe "::redacted_url" do
    it "masks env-token credentials embedded in a push URL" do
      allow(GitHub::API).to receive(:credentials).and_return("ghp_secrettoken")
      expect(described_class.redacted_url(
               "https://x-access-token:ghp_secrettoken@github.com/Homebrew/homebrew-core",
             ))
        .to eq("https://x-access-token:******@github.com/Homebrew/homebrew-core")
    end

    it "leaves a credential-free URL unchanged" do
      allow(GitHub::API).to receive(:credentials).and_return(nil)
      expect(described_class.redacted_url("https://github.com/Homebrew/homebrew-core"))
        .to eq("https://github.com/Homebrew/homebrew-core")
    end
  end

  context "with a third-party tap" do
    sig { returns(Tap) }
    let(:tap) { Tap.fetch("user", "repo") }

    before do
      (tap.path/"Formula").mkpath
      (tap.path/"Formula/foo.rb").write "class Foo < Formula\n  url \"https://brew.sh/foo-1.0.tar.gz\"\nend\n"
      event = mktmpdir/"event.json"
      event.write "{}"
      ENV["GITHUB_EVENT_PATH"] = event.to_s
      ENV["GITHUB_OUTPUT"] = (mktmpdir/"output").to_s
      ENV["GITHUB_SHA"] = "deadbeef"
    end

    after { FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"user" }

    it "prepares bumps for every formula in the tap" do
      expect(described_class).to receive(:system)
        .with(HOMEBREW_BREW_FILE, "bump", "--formulae", "--bump-synced", start_with("--write-pr-to="),
              "--tap=user/repo")
        .and_return(true)
      described_class.prepare_prs((mktmpdir/"bumps.json").to_s, tap)
    end

    it "accepts a prepared bump for any formula in the tap" do
      bumps = mktmpdir/"bumps.json"
      bumps.write JSON.generate(foo: { base: "deadbeef", version: "1.1", formulae: { foo: "" } })
      allow(tap).to receive(:git_head).and_return("deadbeef")
      expect(GitHub::API).to receive(:open_rest)
        .with(having_attributes(query: "head=user%3Abump-foo-1.1&state=all"))
        .and_return([{}])
      described_class.commit_prepared_pr(bumps.to_s, "foo", tap)
    end

    it "accepts a requested alias in the tap and renames it for the new version" do
      formula = tap.path/"Formula/foo.rb"
      tap.alias_dir.mkpath
      FileUtils.ln_s formula, tap.alias_dir/"foo@1"
      File.write ENV.fetch("GITHUB_EVENT_PATH"), JSON.generate(inputs: { formulae: "user/repo/foo@1" })
      bumps = mktmpdir/"bumps.json"
      bumps.write JSON.generate(foo: { base: "deadbeef", version: "2.0",
                                       formulae: { foo: formula.read.sub("1.0", "2.0") } })
      allow(tap).to receive(:git_head).and_return("deadbeef")
      allow(GitHub::API).to receive(:open_rest).and_return([])
      allow(SystemCommand).to receive(:safe_system)
      described_class.commit_prepared_pr(bumps.to_s, "foo", tap)
      expect(tap.alias_dir.children.map { it.basename.to_s }).to eq(["foo@2"])
    end

    it "accepts a requested cask named like a formula alias in the tap" do
      tap.alias_dir.mkpath
      FileUtils.ln_s tap.path/"Formula/foo.rb", tap.alias_dir/"bar"
      File.write ENV.fetch("GITHUB_EVENT_PATH"), JSON.generate(inputs: { casks: "bar" })
      bumps = mktmpdir/"bumps.json"
      bumps.write JSON.generate(bar: { base: "deadbeef", version: "1.1", title: "bar 1.1", casks: { bar: "" } })
      allow(tap).to receive(:git_head).and_return("deadbeef")
      expect(GitHub::API).to receive(:open_rest).and_return([{}])
      described_class.commit_prepared_pr(bumps.to_s, "bar", tap, casks: true)
    end

    it "rejects a prepared bump for a formula outside the tap" do
      expect { described_class.commit_prepared_pr("bumps.json", "bar", tap) }
        .to raise_error(SystemExit).and output(/Unexpected formulae in the prepared bump/).to_stderr
    end

    context "when signing a new branch without a signing key" do
      before do
        allow(Utils).to receive(:safe_popen_read).with("git", "branch", "--show-current").and_return("bump-foo-1.1\n")
        allow(Utils).to receive(:safe_popen_read).with("git", "ls-remote", any_args).and_return("")
        allow(Utils).to receive(:popen_read).with("git", "config", "--get", "user.signingkey").and_return("")
      end

      it "doesn't rebase or sign" do
        expect(SystemCommand).not_to receive(:safe_system)
        described_class.sign_pr(tap)
      end

      it "still writes push=true" do
        described_class.sign_pr(tap)
        expect(File.read(ENV.fetch("GITHUB_OUTPUT"))).to eq("push=true\n")
      end
    end
  end
end
