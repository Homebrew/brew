# typed: true
# frozen_string_literal: true

RSpec.describe Tap do
  subject(:homebrew_foo_tap) { described_class.fetch("Homebrew", "foo") }

  let(:path) { HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-foo" }
  let(:formula_file) { path/"Formula/foo.rb" }
  let(:alias_file) { path/"Aliases/bar" }
  let(:cmd_file) { path/"cmd/brew-tap-cmd.rb" }
  let(:manpage_file) { path/"manpages/brew-tap-cmd.1" }
  let(:bash_completion_file) { path/"completions/bash/brew-tap-cmd" }
  let(:zsh_completion_file) { path/"completions/zsh/_brew-tap-cmd" }
  let(:fish_completion_file) { path/"completions/fish/brew-tap-cmd.fish" }

  include FileUtils

  alias_matcher :have_cask_file, :be_cask_file
  alias_matcher :have_formula_file, :be_formula_file
  alias_matcher :have_custom_remote, :be_custom_remote

  before do
    path.mkpath
    (path/"audit_exceptions").mkpath
    (path/"style_exceptions").mkpath

    # requiring utils/output in tap.rb should be enough but it's not for no apparent reason.
    $stderr.extend(Utils::Output::Mixin)
  end

  def setup_tap_files
    formula_file.dirname.mkpath
    formula_file.write <<~RUBY
      class Foo < Formula
        url "https://brew.sh/foo-1.0.tar.gz"
      end
    RUBY

    alias_file.parent.mkpath
    ln_s formula_file, alias_file

    (path/"formula_renames.json").write <<~JSON
      { "oldname": "foo" }
    JSON

    (path/"tap_migrations.json").write <<~JSON
      { "removed-formula": "homebrew/foo" }
    JSON

    %w[audit_exceptions style_exceptions].each do |exceptions_directory|
      (path/exceptions_directory).mkpath

      (path/"#{exceptions_directory}/formula_list.json").write <<~JSON
        [ "foo", "bar" ]
      JSON

      (path/"#{exceptions_directory}/formula_hash.json").write <<~JSON
        { "foo": "foo1", "bar": "bar1" }
      JSON
    end

    [
      cmd_file,
      manpage_file,
      bash_completion_file,
      zsh_completion_file,
      fish_completion_file,
    ].each do |f|
      f.parent.mkpath
      touch f
    end

    chmod 0755, cmd_file
  end

  def setup_git_repo
    path.cd do
      system "git", "init"
      system "git", "remote", "add", "origin", "https://github.com/Homebrew/homebrew-foo"
      system "git", "add", "--all"
      system "git", "commit", "-m", "init"
    end
  end

  def setup_completion(link:)
    allow(Commands).to receive(:rebuild_commands_completion_list)
    allow(CacheStoreDatabase).to receive(:use).and_call_original
    allow(CacheStoreDatabase).to receive(:use).with(:descriptions)
    allow(CacheStoreDatabase).to receive(:use).with(:cask_descriptions)

    HOMEBREW_REPOSITORY.cd do
      system "git", "init"
      system "git", "config", "--replace-all", "homebrew.linkcompletions", link.to_s
      system "git", "config", "--replace-all", "homebrew.completionsmessageshown", "true"
    end
  end

  specify "::fetch" do
    expect(described_class.fetch("Homebrew", "core")).to be_a(CoreTap)
    expect(described_class.fetch("Homebrew", "homebrew")).to be_a(CoreTap)
    tap = described_class.fetch("Homebrew", "foo")
    expect(tap).to be_a(described_class)
    expect(tap.name).to eq("homebrew/foo")

    expect do
      described_class.fetch("foo")
    end.to raise_error(Tap::InvalidNameError, /Invalid tap name/)

    expect do
      described_class.fetch("homebrew/homebrew/bar")
    end.to raise_error(Tap::InvalidNameError, /Invalid tap name/)

    expect do
      described_class.fetch("homebrew", "homebrew/baz")
    end.to raise_error(Tap::InvalidNameError, /Invalid tap name/)
  end

  describe "::from_path" do
    let(:tap) { described_class.fetch("Homebrew", "core") }
    let(:path) { tap.path }
    let(:formula_path) { path/"Formula/formula.rb" }

    it "returns the Tap for a Formula path" do
      expect(described_class.from_path(formula_path)).to eq tap
    end

    it "returns the Tap when given its exact path" do
      expect(described_class.from_path(path)).to eq tap
    end

    context "when path contains a dot" do
      let(:tap) { described_class.fetch("str4d.xyz", "rage") }

      after do
        tap.uninstall
      end

      it "returns the Tap when given its exact path" do
        expect(described_class.from_path(path)).to eq tap
      end
    end
  end

  describe "::allowed_taps" do
    before { allow(Homebrew::EnvConfig).to receive(:allowed_taps).and_return("homebrew/allowed") }

    it "returns the references from the environment" do
      expect(described_class.allowed_taps).to contain_exactly("homebrew/allowed")
    end

    it "normalises a `user/homebrew-repository` entry to a canonical tap name" do
      allow(Homebrew::EnvConfig).to receive(:allowed_taps).and_return("User/homebrew-Repo")
      expect(described_class.allowed_taps).to contain_exactly("user/repo")
    end

    it "preserves a remote URL entry verbatim" do
      allow(Homebrew::EnvConfig).to receive(:allowed_taps).and_return("https://gitlab.com/other/repo")
      expect(described_class.allowed_taps).to contain_exactly("https://gitlab.com/other/repo")
    end

    it "warns about and ignores an invalid tap name" do
      allow(Homebrew::EnvConfig).to receive(:allowed_taps).and_return("not-a-tap")
      expect { expect(described_class.allowed_taps).to be_empty }.to output(/Invalid tap name/).to_stderr
    end
  end

  describe "::forbidden_taps" do
    before { allow(Homebrew::EnvConfig).to receive(:forbidden_taps).and_return("homebrew/forbidden") }

    it "returns the references from the environment" do
      expect(described_class.forbidden_taps).to contain_exactly("homebrew/forbidden")
    end
  end

  describe "::remote_reference?" do
    it "recognises scp-like syntax without a `user@`" do
      expect(described_class.remote_reference?("ssh_host:/srv/git/homebrew-custom_tap")).to be true
    end

    it "recognises scp-like syntax with a `user@`" do
      expect(described_class.remote_reference?("git@github.com:user/homebrew-repo")).to be true
    end

    it "treats a `user/repository` tap name as not a remote reference" do
      expect(described_class.remote_reference?("user/repo")).to be false
    end

    it "treats a bare `@`-containing string as not a remote reference" do
      expect(described_class.remote_reference?("foo@bar")).to be false
    end

    it "treats a `host:` with an empty path as not a remote reference" do
      expect(described_class.remote_reference?("host:")).to be false
    end
  end

  describe "::normalize_remote" do
    it "keeps an explicit port on a GitHub remote rather than turning it into a path" do
      expect(described_class.normalize_remote("https://github.com:443/Homebrew/homebrew-core"))
        .to eq("https://github.com:443/homebrew/homebrew-core")
    end
  end

  describe "::same_remote?" do
    it "ignores a GitHub `.git` suffix, trailing slash and case" do
      expect(described_class.same_remote?("https://github.com/Homebrew/homebrew-core.git/",
                                          "https://github.com/homebrew/homebrew-core")).to be true
    end

    it "ignores a `.git` suffix on GitLab remotes" do
      expect(described_class.same_remote?("https://gitlab.com/other/repo.git",
                                          "https://gitlab.com/other/repo")).to be true
    end

    it "ignores a trailing slash on GitLab remotes" do
      expect(described_class.same_remote?("https://gitlab.com/other/repo/",
                                          "https://gitlab.com/other/repo")).to be true
    end

    it "keeps a `.git` suffix and trailing slash significant on a self-hosted remote" do
      expect(described_class.same_remote?("https://git.example.com/other/repo.git/",
                                          "https://git.example.com/other/repo")).to be false
    end

    it "still matches non-GitHub remotes case-insensitively" do
      expect(described_class.same_remote?("https://gitlab.com/other/repo",
                                          "https://GitLab.com/Other/Repo")).to be true
    end

    it "keeps non-GitHub remotes with different paths distinct" do
      expect(described_class.same_remote?("https://gitlab.com/other/repo",
                                          "https://gitlab.com/other/other-repo")).to be false
    end

    it "treats a GitHub SSH SCP remote the same as HTTPS" do
      expect(described_class.same_remote?("git@github.com:Homebrew/homebrew-core",
                                          "https://github.com/Homebrew/homebrew-core")).to be true
    end

    it "treats a GitHub ssh:// remote the same as HTTPS" do
      expect(described_class.same_remote?("ssh://git@github.com/Homebrew/homebrew-core",
                                          "https://github.com/Homebrew/homebrew-core")).to be true
    end

    it "treats a GitHub git:// remote the same as HTTPS" do
      expect(described_class.same_remote?("git://github.com/Homebrew/homebrew-core",
                                          "https://github.com/Homebrew/homebrew-core")).to be true
    end

    it "treats a GitHub SSH SCP remote with .git suffix the same as HTTPS" do
      expect(described_class.same_remote?("git@github.com:Homebrew/homebrew-core.git",
                                          "https://github.com/Homebrew/homebrew-core")).to be true
    end

    it "keeps a different host distinct" do
      expect(described_class.same_remote?("https://evil.example/Homebrew/homebrew-core",
                                          "https://github.com/Homebrew/homebrew-core")).to be false
    end
  end

  describe "#matches_reference?" do
    let(:tap) { described_class.fetch("user", "repo") }

    it "matches a default-remote tap by its name" do
      expect(tap.matches_reference?("user/repo", remote: "https://github.com/user/homebrew-repo")).to be true
    end

    it "matches a default-remote tap whose remote has a `.git` suffix" do
      expect(tap.matches_reference?("user/repo", remote: "https://github.com/user/homebrew-repo.git")).to be true
    end

    it "does not match a custom-remote tap by its name" do
      expect(tap.matches_reference?("user/repo", remote: "https://gitlab.com/other/repo")).to be false
    end

    it "matches a custom-remote tap by its remote URL" do
      expect(tap.matches_reference?("https://gitlab.com/other/repo", remote: "https://gitlab.com/other/repo"))
        .to be true
    end

    it "matches a tap by its local path remote" do
      expect(tap.matches_reference?("/Users/me/homebrew-tap", remote: "/Users/me/homebrew-tap")).to be true
    end

    it "matches a GitHub SSH-remote tap by its name" do
      expect(tap.matches_reference?("user/repo", remote: "git@github.com:user/homebrew-repo")).to be true
    end

    it "matches a GitHub SSH-remote tap by its HTTPS URL reference" do
      expect(tap.matches_reference?("https://github.com/user/homebrew-repo",
                                    remote: "git@github.com:user/homebrew-repo")).to be true
    end
  end

  describe "#allowed_by_env?" do
    before { allow(Homebrew::EnvConfig).to receive(:allowed_taps).and_return("user/repo") }

    it "does not allow a name-matched tap fetched from a custom remote" do
      expect(described_class.fetch("user", "repo").allowed_by_env?(remote: "https://evil.example/repo")).to be false
    end

    it "does not implicitly allow an official tap fetched from a custom remote" do
      expect(described_class.fetch("Homebrew",
                                   "foo").allowed_by_env?(remote: "https://evil.example/repo")).to be false
    end
  end

  describe "#implicitly_trusted?" do
    it "is true for an official tap on its default remote" do
      expect(described_class.fetch("Homebrew", "foo")
        .implicitly_trusted?(remote: "https://github.com/Homebrew/homebrew-foo")).to be true
    end

    it "is false for an official tap on a custom remote" do
      expect(described_class.fetch("Homebrew", "foo").implicitly_trusted?(remote: "https://evil.example/repo"))
        .to be false
    end

    it "is true for homebrew/core in API mode regardless of remote" do
      with_env(HOMEBREW_NO_INSTALL_FROM_API: nil) do
        expect(CoreTap.instance.implicitly_trusted?(remote: "https://evil.example/core")).to be true
      end
    end

    it "is true for a homebrew/core Git checkout whose remote has a `.git` suffix" do
      with_env(HOMEBREW_NO_INSTALL_FROM_API: "1") do
        expect(CoreTap.instance.implicitly_trusted?(remote: "https://github.com/Homebrew/homebrew-core.git"))
          .to be true
      end
    end

    it "is false for a homebrew/core Git checkout from a non-official remote" do
      with_env(HOMEBREW_NO_INSTALL_FROM_API: "1") do
        expect(CoreTap.instance.implicitly_trusted?(remote: "https://evil.example/core")).to be false
      end
    end

    it "accepts the configured HOMEBREW_CORE_GIT_REMOTE as official" do
      with_env(HOMEBREW_NO_INSTALL_FROM_API: "1", HOMEBREW_CORE_GIT_REMOTE: "https://mirror.example/core") do
        expect(CoreTap.instance.implicitly_trusted?(remote: "https://mirror.example/core")).to be true
      end
    end
  end

  describe "#forbidden_by_env?" do
    before { allow(Homebrew::EnvConfig).to receive(:forbidden_taps).and_return("https://github.com/evil/homebrew-tap") }

    it "forbids any locally-named tap fetched from a forbidden remote URL" do
      expect(described_class.fetch("notevil", "tap").forbidden_by_env?(remote: "https://github.com/evil/homebrew-tap"))
        .to be true
    end
  end

  specify "attributes" do
    expect(homebrew_foo_tap.user).to eq("Homebrew")
    expect(homebrew_foo_tap.repository).to eq("foo")
    expect(homebrew_foo_tap.name).to eq("homebrew/foo")
    expect(homebrew_foo_tap.path).to eq(path)
    expect(homebrew_foo_tap).to be_installed
    expect(homebrew_foo_tap).to be_official
    expect(homebrew_foo_tap).not_to be_a_core_tap
  end

  specify "#issues_url" do
    t = described_class.fetch("someone", "foo")
    path = HOMEBREW_TAP_DIRECTORY/"someone/homebrew-foo"
    path.mkpath
    cd path do
      system "git", "init"
      system "git", "remote", "add", "origin",
             "https://github.com/someone/homebrew-foo"
    end
    expect(t.issues_url).to eq("https://github.com/someone/homebrew-foo/issues")
    expect(homebrew_foo_tap.issues_url).to eq("https://github.com/Homebrew/homebrew-foo/issues")

    (HOMEBREW_TAP_DIRECTORY/"someone/homebrew-no-git").mkpath
    expect(described_class.fetch("someone", "no-git").issues_url).to be_nil
  ensure
    FileUtils.rm_rf(path.parent)
  end

  specify "files" do
    setup_tap_files

    allow(Homebrew::Trust).to receive(:trusted_tap?).with(homebrew_foo_tap).and_return(true)
    allow(homebrew_foo_tap).to receive_messages(
      cask_tokens:     [],
      remote:          "https://github.com/Homebrew/homebrew-foo",
      custom_remote?:  false,
      private?:        false,
      git_head:        "abc123",
      git_last_commit: "1 day ago",
      git_branch:      "main",
    )

    expect(homebrew_foo_tap.formula_files).to eq([formula_file])
    expect(homebrew_foo_tap.formula_names).to eq(["homebrew/foo/foo"])
    expect(homebrew_foo_tap.alias_files).to eq([alias_file])
    expect(homebrew_foo_tap.aliases).to eq(["homebrew/foo/bar"])
    expect(homebrew_foo_tap.alias_table).to eq("homebrew/foo/bar" => "homebrew/foo/foo")
    expect(homebrew_foo_tap.alias_reverse_table).to eq("homebrew/foo/foo" => ["homebrew/foo/bar"])
    expect(homebrew_foo_tap.formula_renames).to eq("oldname" => "foo")
    expect(homebrew_foo_tap.tap_migrations).to eq("removed-formula" => "homebrew/foo")
    expect(homebrew_foo_tap.command_files).to eq([cmd_file])
    expect(homebrew_foo_tap.to_hash).to eq(
      {
        "name"          => "homebrew/foo",
        "user"          => "Homebrew",
        "repo"          => "foo",
        "repository"    => "foo",
        "path"          => path.to_s,
        "installed"     => true,
        "official"      => true,
        "trusted"       => true,
        "formula_names" => ["homebrew/foo/foo"],
        "cask_tokens"   => [],
        "formula_files" => [formula_file.to_s],
        "cask_files"    => [],
        "command_files" => [cmd_file.to_s],
        "remote"        => "https://github.com/Homebrew/homebrew-foo",
        "custom_remote" => false,
        "private"       => false,
        "HEAD"          => "abc123",
        "last_commit"   => "1 day ago",
        "branch"        => "main",
      },
    )
    expect(homebrew_foo_tap).to have_formula_file("Formula/foo.rb")
    expect(homebrew_foo_tap).not_to have_formula_file("bar.rb")
    expect(homebrew_foo_tap).not_to have_formula_file("Formula/baz.sh")
  end

  describe "#prefix_to_versioned_formulae_names" do
    it "groups versioned full formulae with their matching full formula" do
      homebrew_foo_tap.instance_variable_set(:@prefix_to_versioned_formulae_names, nil)
      allow(homebrew_foo_tap).to receive(:formula_names).and_return(["foo@2.0", "foo-full", "foo@2.0-full"])

      expect(homebrew_foo_tap.prefix_to_versioned_formulae_names)
        .to include("foo" => ["foo@2.0"], "foo-full" => ["foo@2.0-full"])
    end
  end

  describe "#remote" do
    it "returns the remote URL", :needs_network do
      setup_git_repo

      expect(homebrew_foo_tap.remote).to eq("https://github.com/Homebrew/homebrew-foo")
      expect(homebrew_foo_tap).not_to have_custom_remote

      services_tap = described_class.fetch("Homebrew", "test-bot")
      services_tap.path.mkpath
      services_tap.path.cd do
        system "git", "init"
        system "git", "remote", "add", "origin", "https://github.com/Homebrew/homebrew-test-bot"
      end
      expect(services_tap).not_to be_private
    end

    it "returns nil if the Tap is not a Git repository" do
      expect(homebrew_foo_tap.remote).to be_nil
    end

    it "returns nil if Git is not available" do
      setup_git_repo
      allow(Utils::Git).to receive(:available?).and_return(false)
      expect(homebrew_foo_tap.remote).to be_nil
    end
  end

  describe "#remote_repo" do
    it "returns the remote https repository" do
      setup_git_repo

      expect(homebrew_foo_tap.remote_repository).to eq("Homebrew/homebrew-foo")

      services_tap = described_class.fetch("Homebrew", "test-bot")
      services_tap.path.mkpath
      services_tap.path.cd do
        system "git", "init"
        system "git", "remote", "add", "origin", "https://github.com/Homebrew/homebrew-bar"
      end
      expect(services_tap.remote_repository).to eq("Homebrew/homebrew-bar")
    end

    it "returns the remote ssh repository" do
      setup_git_repo

      expect(homebrew_foo_tap.remote_repository).to eq("Homebrew/homebrew-foo")

      services_tap = described_class.fetch("Homebrew", "test-bot")
      services_tap.path.mkpath
      services_tap.path.cd do
        system "git", "init"
        system "git", "remote", "add", "origin", "git@github.com:Homebrew/homebrew-bar"
      end
      expect(services_tap.remote_repository).to eq("Homebrew/homebrew-bar")
    end

    it "returns nil if the Tap is not a Git repository" do
      expect(homebrew_foo_tap.remote_repository).to be_nil
    end

    it "returns nil if Git is not available" do
      setup_git_repo
      allow(Utils::Git).to receive(:available?).and_return(false)
      expect(homebrew_foo_tap.remote_repository).to be_nil
    end
  end

  describe "#custom_remote?" do
    subject(:tap) { described_class.fetch("Homebrew", "test-bot") }

    let(:remote) { nil }

    before do
      tap.path.mkpath
      system "git", "-C", tap.path, "init"
      system "git", "-C", tap.path, "remote", "add", "origin", remote if remote
    end

    context "if no remote is available" do
      it "returns true" do
        expect(tap.remote).to be_nil
        expect(tap.custom_remote?).to be true
      end
    end

    context "when using the default remote" do
      let(:remote) { "https://github.com/Homebrew/homebrew-test-bot" }

      it(:custom_remote?) { expect(tap.custom_remote?).to be false }
    end

    context "when the default remote has a `.git` suffix" do
      let(:remote) { "https://github.com/Homebrew/homebrew-test-bot.git" }

      it(:custom_remote?) { expect(tap.custom_remote?).to be false }
    end

    context "when using the SSH SCP remote for the same repository" do
      let(:remote) { "git@github.com:Homebrew/homebrew-test-bot" }

      it(:custom_remote?) { expect(tap.custom_remote?).to be false }
    end

    context "when using a truly non-default remote" do
      let(:remote) { "https://gitlab.com/Homebrew/homebrew-test-bot" }

      it(:custom_remote?) { expect(tap.custom_remote?).to be true }
    end
  end

  describe "#update_remote_from_git_redirect!" do
    it "moves default GitHub taps to the redirected name and invalidates old trust", :trust_store do
      require "trust"

      tap = described_class.fetch("oldowner", "foo")
      old_path = tap.path
      new_path = described_class.fetch("newowner", "foo").path
      tap.path.mkpath
      system "git", "-C", tap.path.to_s, "init"
      system "git", "-C", tap.path.to_s, "remote", "add", "origin", "https://github.com/oldowner/homebrew-foo"
      Homebrew::Trust.trust!(:tap, "oldowner/foo")
      Homebrew::Trust.trust!(:tap, "https://github.com/oldowner/homebrew-foo")
      Homebrew::Trust.trust!(:formula, "oldowner/foo/bar")

      tap.update_remote_from_git_redirect!(
        "warning: redirecting to https://github.com/newowner/homebrew-foo\n",
        quiet: true,
      )

      expect(tap.name).to eq("newowner/foo")
      expect(tap.path).to eq(new_path)
      expect(new_path).to be_a_directory
      expect(old_path).not_to exist
      expect(Utils.popen_read("git", "-C", tap.path, "config", "remote.origin.url").chomp)
        .to eq("https://github.com/newowner/homebrew-foo")
      expect(Homebrew::Trust.trusted_entries(:tap)).to be_empty
      expect(Homebrew::Trust.trusted_entries(:formula)).to be_empty
    ensure
      Homebrew::Trust.clear!(:tap)
      Homebrew::Trust.clear!(:formula)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"oldowner"
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"newowner"
    end

    it "prints tap redirect and untrust messages", :trust_store do
      require "trust"

      tap = described_class.fetch("oldoutput", "foo")
      tap.path.mkpath
      system "git", "-C", tap.path.to_s, "init"
      system "git", "-C", tap.path.to_s, "remote", "add", "origin", "https://github.com/oldoutput/homebrew-foo"
      Homebrew::Trust.trust!(:tap, "oldoutput/foo")

      expect($stderr).to receive(:ohai).with("Redirected tap oldoutput/foo to tap newoutput/foo")
      expect($stderr).to receive(:puts).with("Untrusted tap: oldoutput/foo")

      tap.update_remote_from_git_redirect!(
        "warning: redirecting to https://github.com/newoutput/homebrew-foo\n",
      )
    ensure
      Homebrew::Trust.clear!(:tap)
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"oldoutput"
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"newoutput"
    end
  end

  specify "Git variant" do
    touch path/"README"
    setup_git_repo

    expect(homebrew_foo_tap.git_head).to eq("0453e16c8e3fac73104da50927a86221ca0740c2")
    expect(homebrew_foo_tap.git_last_commit).to match(/\A\d+ .+ ago\Z/)
  end

  specify "#private?", :needs_network do
    expect(homebrew_foo_tap).to be_private
  end

  describe "#install" do
    it "raises an error when the Tap is already tapped" do
      setup_git_repo
      already_tapped_tap = described_class.fetch("Homebrew", "foo")
      expect(already_tapped_tap).to be_installed
      expect { already_tapped_tap.install }.to raise_error(TapAlreadyTappedError)
    end

    it "raises an error when the Tap is already tapped with the right remote" do
      setup_git_repo
      already_tapped_tap = described_class.fetch("Homebrew", "foo")
      expect(already_tapped_tap).to be_installed
      right_remote = homebrew_foo_tap.remote
      expect { already_tapped_tap.install clone_target: right_remote }.to raise_error(TapAlreadyTappedError)
    end

    it "refuses a name-allowed tap cloned from a custom remote (no HOMEBREW_ALLOWED_TAPS bypass)" do
      allow(Homebrew::EnvConfig).to receive(:allowed_taps).and_return("user/repo")
      tap = described_class.fetch("user", "repo")

      expect { tap.install clone_target: "https://evil.example/repo" }.to raise_error(SystemExit)
      expect(tap).not_to be_installed
    end

    it "raises an error when the remote doesn't match" do
      setup_git_repo
      already_tapped_tap = described_class.fetch("Homebrew", "foo")
      expect(already_tapped_tap).to be_installed
      wrong_remote = "#{homebrew_foo_tap.remote}-oops"
      expect do
        already_tapped_tap.install clone_target: wrong_remote
      end.to raise_error(TapRemoteMismatchError)
    end

    it "raises an error when the remote for Homebrew/core doesn't match HOMEBREW_CORE_GIT_REMOTE" do
      core_tap = described_class.fetch("Homebrew", "core")
      wrong_remote = "#{Homebrew::EnvConfig.core_git_remote}-oops"
      expect do
        core_tap.install clone_target: wrong_remote
      end.to raise_error(TapCoreRemoteMismatchError)
    end

    it "creates core and cask taps as worktrees when the brew source repository has them" do
      source_repository = HOMEBREW_PREFIX.parent/"source-repository"
      worktree_git_dir = HOMEBREW_REPOSITORY/".git"

      allow(Commands).to receive(:rebuild_commands_completion_list)
      allow(CacheStoreDatabase).to receive(:use).and_call_original
      allow(CacheStoreDatabase).to receive(:use).with(:descriptions)
      allow(CacheStoreDatabase).to receive(:use).with(:cask_descriptions)

      [CoreTap.instance, CoreCaskTap.instance].each do |tap|
        source_tap = source_repository/"Library/Taps/#{tap.full_name.downcase}"

        FileUtils.rm_rf tap.path
        source_tap.mkpath
        source_tap.cd do
          system "git", "init"
          FileUtils.touch "README.md"
          system "git", "add", "--all"
          system "git", "commit", "-m", "init"
        end
        FileUtils.mkdir_p worktree_git_dir.dirname
        worktree_git_dir.write "gitdir: #{source_repository}/.git/worktrees/#{HOMEBREW_REPOSITORY.basename}\n"

        allow(tap).to receive_messages(command_files: [], formula_files: [], cask_files: [],
                                       formula_names: [], cask_tokens: [], link_completions_and_manpages: nil)
        expect(tap).to receive(:safe_system)
          .with("git", "-C", source_tap, "worktree", "add", "--detach", tap.path, "HEAD")
          .and_wrap_original do
            tap.path.mkpath
            (tap.path/".git").write "gitdir: #{source_tap}/.git/worktrees/#{tap.full_repository.downcase}\n"
          end

        tap.install
      end
    ensure
      FileUtils.rm_rf source_repository
      FileUtils.rm_rf CoreTap.instance.path
      FileUtils.rm_rf CoreCaskTap.instance.path
      (CoreTap.instance.path/"Formula").mkpath
    end

    it "creates a tap from another brew worktree when that has the source repository" do
      tap = CoreCaskTap.instance
      source_repository = HOMEBREW_PREFIX.parent/"source-repository"
      source_worktree = HOMEBREW_PREFIX.parent/"source-worktree"
      source_tap = source_worktree/"Library/Taps/#{tap.full_name.downcase}"

      allow(Commands).to receive(:rebuild_commands_completion_list)
      allow(CacheStoreDatabase).to receive(:use).and_call_original
      allow(CacheStoreDatabase).to receive(:use).with(:descriptions)
      allow(CacheStoreDatabase).to receive(:use).with(:cask_descriptions)

      FileUtils.rm_rf tap.path
      source_tap.mkpath
      source_tap.cd do
        system "git", "init"
        FileUtils.touch "README.md"
        system "git", "add", "--all"
        system "git", "commit", "-m", "init"
      end
      FileUtils.mkdir_p (HOMEBREW_REPOSITORY/".git").dirname
      (HOMEBREW_REPOSITORY/".git")
        .write "gitdir: #{source_repository}/.git/worktrees/#{HOMEBREW_REPOSITORY.basename}\n"

      allow(Utils).to receive(:popen_read).and_call_original
      allow(Utils).to receive(:popen_read)
        .with("git", "-C", HOMEBREW_REPOSITORY, "worktree", "list", "--porcelain")
        .and_return("worktree #{source_worktree}\n")
      allow(tap).to receive_messages(command_files: [], formula_files: [], cask_files: [],
                                     formula_names: [], cask_tokens: [], link_completions_and_manpages: nil)
      expect(tap).to receive(:safe_system)
        .with("git", "-C", source_tap, "worktree", "add", "--detach", tap.path, "HEAD")
        .and_wrap_original do
          tap.path.mkpath
          (tap.path/".git").write "gitdir: #{source_tap}/.git/worktrees/#{tap.full_repository.downcase}\n"
        end

      tap.install
    ensure
      FileUtils.rm_rf source_repository
      FileUtils.rm_rf source_worktree
      FileUtils.rm_rf CoreCaskTap.instance.path
    end

    it "uses the requested remote for cask taps with an explicit clone target" do
      tap = CoreCaskTap.instance
      requested_remote = "https://example.com/Homebrew/homebrew-cask"
      source_repository = HOMEBREW_PREFIX.parent/"source-repository"
      source_tap = source_repository/"Library/Taps/#{tap.full_name.downcase}"

      allow(Commands).to receive(:rebuild_commands_completion_list)
      allow(CacheStoreDatabase).to receive(:use).and_call_original
      allow(CacheStoreDatabase).to receive(:use).with(:descriptions)
      allow(CacheStoreDatabase).to receive(:use).with(:cask_descriptions)

      FileUtils.rm_rf tap.path
      source_tap.mkpath
      (source_tap/".git").mkpath
      FileUtils.mkdir_p (HOMEBREW_REPOSITORY/".git").dirname
      (HOMEBREW_REPOSITORY/".git")
        .write "gitdir: #{source_repository}/.git/worktrees/#{HOMEBREW_REPOSITORY.basename}\n"

      allow(tap).to receive_messages(command_files: [], formula_files: [], cask_files: [],
                                     formula_names: [], cask_tokens: [], link_completions_and_manpages: nil)
      expect(tap).to receive(:git_command!)
        .with(["clone", requested_remote, tap.path.to_s, "--origin=origin", "--template=",
               "--config", "core.fsmonitor=false"])
        .and_wrap_original do
          tap.path.mkpath
          (tap.path/".git").mkpath
          double(stderr: "")
        end

      tap.install clone_target: requested_remote, force: true
    ensure
      FileUtils.rm_rf source_repository
      FileUtils.rm_rf CoreCaskTap.instance.path
    end

    it "raises an error when run `brew tap --custom-remote` without a custom remote (already installed)" do
      setup_git_repo
      already_tapped_tap = described_class.fetch("Homebrew", "foo")
      expect(already_tapped_tap).to be_installed

      expect do
        already_tapped_tap.install clone_target: nil, custom_remote: true
      end.to raise_error(TapNoCustomRemoteError)
    end

    it "raises an error when run `brew tap --custom-remote` without a custom remote (not installed)" do
      not_tapped_tap = described_class.fetch("Homebrew", "bar")
      expect(not_tapped_tap).not_to be_installed

      expect do
        not_tapped_tap.install clone_target: nil, custom_remote: true
      end.to raise_error(TapNoCustomRemoteError)
    end

    specify "Git error" do
      tap = described_class.fetch("user", "repo")

      expect do
        tap.install clone_target: "file:///not/existed/remote/url"
      end.to raise_error(ErrorDuringExecution)

      expect(tap).not_to be_installed
      expect(HOMEBREW_TAP_DIRECTORY/"user").not_to exist
    end
  end

  describe "#uninstall" do
    it "raises an error if the Tap is not available" do
      tap = described_class.fetch("Homebrew", "bar")
      expect { tap.uninstall }.to raise_error(TapUnavailableError)
    end

    it "removes Git worktree metadata for worktree-installed taps" do
      tap = CoreCaskTap.instance
      source_tap = HOMEBREW_PREFIX.parent/"source-tap"

      FileUtils.rm_rf tap.path
      source_tap.mkpath
      (source_tap/".git").mkpath
      tap.path.mkpath
      (tap.path/".git").write "gitdir: #{source_tap}/.git/worktrees/#{tap.full_repository.downcase}\n"

      allow(tap).to receive_messages(contents: [], formula_names: [], cask_tokens: [])
      expect(tap).to receive(:safe_system)
        .with("git", "-C", source_tap, "worktree", "remove", "--force", tap.path)

      tap.uninstall
    ensure
      FileUtils.rm_rf source_tap
      FileUtils.rm_rf CoreCaskTap.instance.path
    end
  end

  specify "#install and #uninstall" do
    setup_tap_files
    setup_git_repo
    setup_completion link: true

    tap = described_class.fetch("Homebrew", "bar")

    tap.install clone_target: homebrew_foo_tap.path/".git"

    expect(tap).to be_installed
    expect(HOMEBREW_PREFIX/"share/man/man1/brew-tap-cmd.1").to be_a_file
    expect(HOMEBREW_PREFIX/"etc/bash_completion.d/brew-tap-cmd").to be_a_file
    expect(HOMEBREW_PREFIX/"share/zsh/site-functions/_brew-tap-cmd").to be_a_file
    expect(HOMEBREW_PREFIX/"share/fish/vendor_completions.d/brew-tap-cmd.fish").to be_a_file
    tap.uninstall

    expect(tap).not_to be_installed
    expect(HOMEBREW_PREFIX/"share/man/man1/brew-tap-cmd.1").not_to exist
    expect(HOMEBREW_PREFIX/"share/man/man1").not_to exist
    expect(HOMEBREW_PREFIX/"etc/bash_completion.d/brew-tap-cmd").not_to exist
    expect(HOMEBREW_PREFIX/"share/zsh/site-functions/_brew-tap-cmd").not_to exist
    expect(HOMEBREW_PREFIX/"share/fish/vendor_completions.d/brew-tap-cmd.fish").not_to exist
  ensure
    FileUtils.rm_r(HOMEBREW_PREFIX/"etc") if (HOMEBREW_PREFIX/"etc").exist?
    FileUtils.rm_r(HOMEBREW_PREFIX/"share") if (HOMEBREW_PREFIX/"share").exist?
  end

  specify "#link_completions_and_manpages when completions are enabled for non-official tap" do
    tap = T.let(nil, T.untyped)
    setup_tap_files
    setup_git_repo
    setup_completion link: true
    tap = described_class.fetch("NotHomebrew", "baz")
    tap.install clone_target: homebrew_foo_tap.path/".git"
    (HOMEBREW_PREFIX/"share/man/man1/brew-tap-cmd.1").delete
    (HOMEBREW_PREFIX/"etc/bash_completion.d/brew-tap-cmd").delete
    (HOMEBREW_PREFIX/"share/zsh/site-functions/_brew-tap-cmd").delete
    (HOMEBREW_PREFIX/"share/fish/vendor_completions.d/brew-tap-cmd.fish").delete
    tap.link_completions_and_manpages
    expect(HOMEBREW_PREFIX/"share/man/man1/brew-tap-cmd.1").to be_a_file
    expect(HOMEBREW_PREFIX/"etc/bash_completion.d/brew-tap-cmd").to be_a_file
    expect(HOMEBREW_PREFIX/"share/zsh/site-functions/_brew-tap-cmd").to be_a_file
    expect(HOMEBREW_PREFIX/"share/fish/vendor_completions.d/brew-tap-cmd.fish").to be_a_file
    tap.uninstall
  ensure
    tap.uninstall if tap&.installed?
    FileUtils.rm_r(HOMEBREW_PREFIX/"etc") if (HOMEBREW_PREFIX/"etc").exist?
    FileUtils.rm_r(HOMEBREW_PREFIX/"share") if (HOMEBREW_PREFIX/"share").exist?
  end

  specify "#link_completions_and_manpages when completions are disabled for non-official tap" do
    tap = T.let(nil, T.untyped)
    setup_tap_files
    setup_git_repo
    setup_completion link: false
    tap = described_class.fetch("NotHomebrew", "baz")
    tap.install clone_target: homebrew_foo_tap.path/".git"
    (HOMEBREW_PREFIX/"share/man/man1/brew-tap-cmd.1").delete
    tap.link_completions_and_manpages
    expect(HOMEBREW_PREFIX/"share/man/man1/brew-tap-cmd.1").to be_a_file
    expect(HOMEBREW_PREFIX/"etc/bash_completion.d/brew-tap-cmd").not_to be_a_file
    expect(HOMEBREW_PREFIX/"share/zsh/site-functions/_brew-tap-cmd").not_to be_a_file
    expect(HOMEBREW_PREFIX/"share/fish/vendor_completions.d/brew-tap-cmd.fish").not_to be_a_file
    tap.uninstall
  ensure
    tap.uninstall if tap&.installed?
    FileUtils.rm_r(HOMEBREW_PREFIX/"etc") if (HOMEBREW_PREFIX/"etc").exist?
    FileUtils.rm_r(HOMEBREW_PREFIX/"share") if (HOMEBREW_PREFIX/"share").exist?
  end

  specify "#link_completions_and_manpages when completions are enabled for official tap" do
    setup_tap_files
    setup_git_repo
    setup_completion link: false
    tap = described_class.fetch("Homebrew", "baz")
    tap.install clone_target: homebrew_foo_tap.path/".git"
    (HOMEBREW_PREFIX/"share/man/man1/brew-tap-cmd.1").delete
    (HOMEBREW_PREFIX/"etc/bash_completion.d/brew-tap-cmd").delete
    (HOMEBREW_PREFIX/"share/zsh/site-functions/_brew-tap-cmd").delete
    (HOMEBREW_PREFIX/"share/fish/vendor_completions.d/brew-tap-cmd.fish").delete
    tap.link_completions_and_manpages
    expect(HOMEBREW_PREFIX/"share/man/man1/brew-tap-cmd.1").to be_a_file
    expect(HOMEBREW_PREFIX/"etc/bash_completion.d/brew-tap-cmd").to be_a_file
    expect(HOMEBREW_PREFIX/"share/zsh/site-functions/_brew-tap-cmd").to be_a_file
    expect(HOMEBREW_PREFIX/"share/fish/vendor_completions.d/brew-tap-cmd.fish").to be_a_file
    tap.uninstall
  ensure
    FileUtils.rm_r(HOMEBREW_PREFIX/"etc") if (HOMEBREW_PREFIX/"etc").exist?
    FileUtils.rm_r(HOMEBREW_PREFIX/"share") if (HOMEBREW_PREFIX/"share").exist?
  end

  specify "#config" do
    setup_git_repo

    expect(homebrew_foo_tap.config[:foo]).to be_nil
    homebrew_foo_tap.config[:foo] = true
    expect(homebrew_foo_tap.config[:foo]).to be true
    homebrew_foo_tap.config.delete(:foo)
    expect(homebrew_foo_tap.config[:foo]).to be_nil
  end

  describe ".each" do
    it "returns an enumerator if no block is passed" do
      expect(described_class.each).to be_an_instance_of(Enumerator)
    end

    context "when the core tap is not installed" do
      around do |example|
        FileUtils.rm_rf CoreTap.instance.path
        example.run
      ensure
        (CoreTap.instance.path/"Formula").mkpath
      end

      it "includes the core tap with the api" do
        expect(described_class.to_a).to include(CoreTap.instance)
      end

      it "omits the core tap without the api", :no_api do
        expect(described_class.to_a).not_to include(CoreTap.instance)
      end
    end
  end

  describe ".installed" do
    it "includes only installed taps" do
      expect(described_class.installed)
        .to contain_exactly(CoreTap.instance, described_class.fetch("homebrew/foo"))
    end
  end

  describe ".all" do
    it "includes the core and cask taps by default", :needs_macos do
      expect(described_class.all).to contain_exactly(
        CoreTap.instance,
        CoreCaskTap.instance,
        described_class.fetch("homebrew/foo"),
        described_class.fetch("third-party/tap"),
      )
    end

    it "includes the core and cask taps by default", :needs_linux do
      expect(described_class.all).to contain_exactly(
        CoreTap.instance,
        CoreCaskTap.instance,
        described_class.fetch("homebrew/foo"),
      )
    end
  end

  describe "Formula Lists" do
    describe "#formula_renames" do
      it "returns the formula_renames hash" do
        setup_tap_files

        expected_result = { "oldname" => "foo" }
        expect(homebrew_foo_tap.formula_renames).to eq expected_result
      end
    end

    describe "#tap_migrations" do
      it "returns the tap_migrations hash" do
        setup_tap_files

        expected_result = { "removed-formula" => "homebrew/foo" }
        expect(homebrew_foo_tap.tap_migrations).to eq expected_result
      end
    end

    describe "tap migration renames" do
      before do
        (path/"tap_migrations.json").write <<~JSON
          {
            "adobe-air-sdk": "homebrew/cask",
            "app-engine-go-32": "homebrew/cask/google-cloud-sdk",
            "app-engine-go-64": "homebrew/cask/google-cloud-sdk",
            "gimp": "homebrew/cask",
            "horndis": "homebrew/cask",
            "inkscape": "homebrew/cask",
            "schismtracker": "homebrew/cask/schism-tracker"
          }
        JSON
      end

      describe "#reverse_tap_migration_renames" do
        it "returns the expected hash" do
          expect(homebrew_foo_tap.reverse_tap_migrations_renames).to eq({
            "homebrew/cask/google-cloud-sdk" => %w[app-engine-go-32 app-engine-go-64],
            "homebrew/cask/schism-tracker"   => %w[schismtracker],
          })
        end
      end

      describe ".tap_migration_oldnames" do
        let(:cask_tap) { CoreCaskTap.instance }
        let(:core_tap) { CoreTap.instance }

        it "returns expected renames", :no_api do
          [
            [cask_tap, "gimp", []],
            [core_tap, "schism-tracker", []],
            [cask_tap, "schism-tracker", %w[schismtracker]],
            [cask_tap, "google-cloud-sdk", %w[app-engine-go-32 app-engine-go-64]],
          ].each do |tap, name, result|
            expect(described_class.tap_migration_oldnames(tap, name)).to eq(result)
          end
        end
      end
    end

    describe "#audit_exceptions" do
      it "returns the audit_exceptions hash" do
        setup_tap_files

        expected_result = {
          formula_list: ["foo", "bar"],
          formula_hash: { "foo" => "foo1", "bar" => "bar1" },
        }
        expect(homebrew_foo_tap.audit_exceptions).to eq expected_result
      end
    end

    describe "#style_exceptions" do
      it "returns the style_exceptions hash" do
        setup_tap_files

        expected_result = {
          formula_list: ["foo", "bar"],
          formula_hash: { "foo" => "foo1", "bar" => "bar1" },
        }
        expect(homebrew_foo_tap.style_exceptions).to eq expected_result
      end
    end

    describe "#formula_file?" do
      it "matches files from Formula/" do
        tap = described_class.fetch("hard/core")
        FileUtils.mkdir_p(tap.path/"Formula")

        %w[
          kvazaar.rb
          Casks/kvazaar.rb
          Casks/k/kvazaar.rb
          Formula/kvazaar.sh
          HomebrewFormula/kvazaar.rb
          HomebrewFormula/k/kvazaar.rb
        ].each do |relative_path|
          expect(tap).not_to have_formula_file(relative_path)
        end

        %w[
          Formula/kvazaar.rb
          Formula/k/kvazaar.rb
        ].each do |relative_path|
          expect(tap).to have_formula_file(relative_path)
        end
      ensure
        FileUtils.rm_rf(tap.path.parent) if tap
      end

      it "matches files from HomebrewFormula/" do
        tap = described_class.fetch("hard/core")
        FileUtils.mkdir_p(tap.path/"HomebrewFormula")

        %w[
          kvazaar.rb
          Casks/kvazaar.rb
          Casks/k/kvazaar.rb
          Formula/kvazaar.rb
          Formula/k/kvazaar.rb
          HomebrewFormula/kvazaar.sh
        ].each do |relative_path|
          expect(tap).not_to have_formula_file(relative_path)
        end

        %w[
          HomebrewFormula/kvazaar.rb
          HomebrewFormula/k/kvazaar.rb
        ].each do |relative_path|
          expect(tap).to have_formula_file(relative_path)
        end
      ensure
        FileUtils.rm_rf(tap.path.parent) if tap
      end

      it "matches files from the top-level directory" do
        tap = described_class.fetch("hard/core")
        FileUtils.mkdir_p(tap.path)

        %w[
          kvazaar.sh
          Casks/kvazaar.rb
          Casks/k/kvazaar.rb
          Formula/kvazaar.rb
          Formula/k/kvazaar.rb
          HomebrewFormula/kvazaar.rb
          HomebrewFormula/k/kvazaar.rb
        ].each do |relative_path|
          expect(tap).not_to have_formula_file(relative_path)
        end

        expect(tap).to have_formula_file("kvazaar.rb")
      ensure
        FileUtils.rm_rf(tap.path.parent) if tap
      end
    end

    describe "#cask_file?" do
      it "matches files from Casks/" do
        tap = described_class.fetch("hard/core")

        %w[
          kvazaar.rb
          Casks/kvazaar.sh
          Formula/kvazaar.rb
          Formula/k/kvazaar.rb
          HomebrewFormula/kvazaar.rb
          HomebrewFormula/k/kvazaar.rb
        ].each do |relative_path|
          expect(tap).not_to have_cask_file(relative_path)
        end

        %w[
          Casks/kvazaar.rb
          Casks/k/kvazaar.rb
        ].each do |relative_path|
          expect(tap).to have_cask_file(relative_path)
        end
      end
    end
  end

  describe CoreTap do
    subject(:core_tap) { described_class.instance }

    specify "attributes" do
      expect(core_tap.user).to eq("Homebrew")
      expect(core_tap.repository).to eq("core")
      expect(core_tap.name).to eq("homebrew/core")
      expect(core_tap.command_files).to eq([])
      expect(core_tap).to be_installed
      expect(core_tap).to be_official
      expect(core_tap).to be_a_core_tap
    end

    specify "forbidden operations", :no_api do
      expect { core_tap.uninstall }.to raise_error(RuntimeError)
    end

    specify "#autobump reads public formula API metadata" do
      core_tap.remove_instance_variable(:@autobump) if core_tap.instance_variable_defined?(:@autobump)
      expect(Homebrew::API::Internal).not_to receive(:formula_hashes)
      allow(Homebrew::API::Formula).to receive(:all_formulae).and_return({
        "autobumped" => { "autobump" => true, "skip_livecheck" => false },
        "disabled"   => { "autobump" => true, "disabled" => true },
        "skipped"    => { "autobump" => true, "skip_livecheck" => true },
      })

      expect(core_tap.autobump).to eq(["autobumped"])
    end

    specify "#autobump reads public cask API metadata" do
      cask_tap = CoreCaskTap.instance
      cask_tap.remove_instance_variable(:@autobump) if cask_tap.instance_variable_defined?(:@autobump)
      expect(Homebrew::API::Formula).not_to receive(:all_formulae)
      expect(Homebrew::API::Internal).not_to receive(:cask_hashes)
      allow(Homebrew::API::Cask).to receive(:all_casks).and_return({
        "autobumped" => { "autobump" => true, "skip_livecheck" => false },
        "disabled"   => { "autobump" => true, "disabled" => true },
        "skipped"    => { "autobump" => true, "skip_livecheck" => true },
      })

      expect(cask_tap.autobump).to eq(["autobumped"])
    end

    specify "files", :no_api do
      path = HOMEBREW_TAP_DIRECTORY/"homebrew/homebrew-core"
      formula_file = core_tap.formula_dir/"foo.rb"
      core_tap.formula_dir.mkpath
      formula_file.write <<~RUBY
        class Foo < Formula
          url "https://brew.sh/foo-1.0.tar.gz"
        end
      RUBY

      formula_list_file_json = '{ "foo": "foo1", "bar": "bar1" }'
      formula_list_file_contents = { "foo" => "foo1", "bar" => "bar1" }
      %w[
        formula_renames.json
        tap_migrations.json
        audit_exceptions/formula_list.json
        style_exceptions/formula_hash.json
      ].each do |file|
        (path/file).dirname.mkpath
        (path/file).write formula_list_file_json
      end

      alias_file = core_tap.alias_dir/"bar"
      alias_file.parent.mkpath
      ln_s formula_file, alias_file

      expect(core_tap.formula_files).to eq([formula_file])
      expect(core_tap.formula_names).to eq(["foo"])
      expect(core_tap.alias_files).to eq([alias_file])
      expect(core_tap.aliases).to eq(["bar"])
      expect(core_tap.alias_table).to eq("bar" => "foo")
      expect(core_tap.alias_reverse_table).to eq("foo" => ["bar"])

      expect(core_tap.formula_renames).to eq formula_list_file_contents
      expect(core_tap.tap_migrations).to eq formula_list_file_contents
      expect(core_tap.audit_exceptions).to eq({ formula_list: formula_list_file_contents })
      expect(core_tap.style_exceptions).to eq({ formula_hash: formula_list_file_contents })
    end
  end

  describe "#repository_var_suffix" do
    specify do
      expect(CoreTap.instance.repository_var_suffix).to eq "_HOMEBREW_HOMEBREW_CORE"
      expect(
        described_class.fetch("my", "tap-with-dashes").repository_var_suffix,
      ).to eq "_MY_HOMEBREW_TAP_WITH_DASHES"
      expect(
        described_class.fetch("my", "tap-with-@-symbol").repository_var_suffix,
      ).to eq "_MY_HOMEBREW_TAP_WITH___SYMBOL"
    end
  end

  describe "::with_formula_name" do
    it "returns the tap and formula name when given a full name" do
      expect(described_class.with_formula_name("homebrew/core/gcc")).to eq [CoreTap.instance, "gcc"]
    end

    it "returns nil when given a relative path" do
      expect(described_class.with_formula_name("./Formula/gcc.rb")).to be_nil
    end
  end

  describe "::with_cask_token" do
    it "returns the tap and cask token when given a full token" do
      expect(described_class.with_cask_token("homebrew/cask/alfred")).to eq [CoreCaskTap.instance, "alfred"]
    end

    it "returns nil when given a relative path" do
      expect(described_class.with_cask_token("./Casks/alfred.rb")).to be_nil
    end
  end
end
