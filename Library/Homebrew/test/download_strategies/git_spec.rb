# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe GitDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version) }

  let(:name) { "baz" }
  let(:url) { "https://github.com/homebrew/foo" }
  let(:version) { nil }
  let(:cached_location) { subject.cached_location }

  before do
    @commit_id = 1
    FileUtils.mkpath cached_location
  end

  describe "#clone_args" do
    it "terminates options before the URL" do
      expect(strategy.clone_args).to end_with("--end-of-options", url, cached_location.to_s)
    end
  end

  describe "#fetch" do
    it "aborts the download if Git cannot be installed" do
      allow(Utils::Git).to receive(:ensure_installed!).and_raise("Git installation failed")
      allow(strategy).to receive(:repo_valid?).and_return(true)
      allow(strategy).to receive(:update)

      expect { strategy.fetch }.to raise_error("Git installation failed")
    end
  end

  describe "#command_sandbox" do
    let(:home) { mktmpdir }

    before do
      allow(Sandbox).to receive(:isolate_operation?).and_return(true)
      allow(Dir).to receive(:home).with(ENV.fetch("USER")).and_return(home.to_s)
      allow(strategy).to receive(:fetching?).and_return(true)
    end

    test_each(["git@git.example.com:repo.git", "https://git.example.com/repo.git"]) do |git_url|
      context "with #{git_url}" do
        let(:url) { git_url }

        it "allows user configuration and agent sockets during downloads" do
          expect(strategy.command_sandbox.profile.rules.select do |rule|
            rule.operation == "network*" || rule.filter&.path == home.to_s
          end).to contain_exactly(
            have_attributes(allow: true, operation: "network*",
                            filter: have_attributes(path: "/", type: :subpath)),
          )
        end
      end
    end

    it "blocks unrelated credentials while allowing Git and SSH configuration" do
      %w[.aws/credentials .npmrc .ssh/config .gitconfig .git-credentials .netrc
         .config/gh/hosts.yml dotfiles/ssh_config].each do |path|
        (home/path).dirname.mkpath
        (home/path).write("")
      end

      expect(strategy.command_sandbox.profile.rules.filter_map do |rule|
        rule.filter&.path if !rule.allow && rule.operation == "file-read*"
      end).to contain_exactly((home/".aws").to_s, (home/".npmrc").to_s)
    end

    context "with a login keychain" do
      let(:keychain) { home/"Library/Keychains/login.keychain-db" }

      before do
        keychain.dirname.mkpath
        FileUtils.touch keychain
        FileUtils.touch keychain.dirname/"metadata.keychain-db"
      end

      test_each(%w[http://git.example.com/repo.git https://git.example.com/repo.git
                   git@git.example.com:repo.git git://git.example.com/repo.git file:///repo.git]) do |git_url|
        context "with #{git_url}" do
          let(:url) { git_url }

          it "denies keychain reads throughout the fetch" do
            keychains = keychain.dirname.realpath.to_s

            expect(strategy.command_sandbox.profile.rules.filter_map do |rule|
              next if rule.operation != "file-read*" || !rule.filter&.path&.start_with?(keychains)

              [rule.allow, rule.filter&.path, rule.filter&.type]
            end).to eq([[false, keychains, :subpath]])
          end
        end
      end
    end

    it "does not probe Git or SSH configuration" do
      expect(SystemCommand).not_to receive(:run)

      strategy.command_sandbox
    end

    it "keeps writes restricted to the cached repository" do
      expect(strategy.command_sandbox.profile.rules.filter_map do |rule|
        rule.filter&.path if rule.allow && rule.operation == "file-write*"
      end).to eq([cached_location.to_s])
    end

    it "restricts home reads and network access during local inspection" do
      allow(strategy).to receive(:fetching?).and_return(false)

      expect(strategy.command_sandbox.profile.rules.select do |rule|
        rule.operation == "network*" || rule.filter&.path == home.to_s
      end).to contain_exactly(
        have_attributes(allow: false, operation: "file-read*",
                        filter: have_attributes(path: home.to_s, type: :subpath)),
        have_attributes(allow: false, operation: "network*", filter: nil),
      )
    end
  end

  describe "#env" do
    subject(:strategy) do
      Class.new(described_class) do
        T.bind(self, T.class_of(GitDownloadStrategy))
        public :env
      end.new(url, name, version)
    end

    before do
      allow(Sandbox).to receive(:isolate_operation?).and_return(true)
      ENV.delete("HOMEBREW_GITHUB_API_TOKEN")
      ENV["SSH_AUTH_SOCK"] = "/path/to/agent.sock"
    end

    it "preserves the download environment even for URLs that may be rewritten to SSH" do
      allow(strategy).to receive(:fetching?).and_return(true)
      ENV["PATH"] = "/path/to/shims:/usr/bin:/bin"
      stub_const("ORIGINAL_PATHS", [Pathname("/path/to/bin"), Pathname("/usr/bin")])

      expect(strategy.env).to eq(
        "GIT_TERMINAL_PROMPT" => "0",
        "HOME"                => Dir.home(ENV.fetch("USER")),
        "PATH"                => "/path/to/shims:/usr/bin:/bin:/path/to/bin",
        "SSH_AUTH_SOCK"       => ENV.fetch("SSH_AUTH_SOCK"),
        "SSH_ASKPASS"         => "/usr/bin/false",
        "SSH_ASKPASS_REQUIRE" => "force",
      )
    end

    it "fails instead of waiting for an SSH key passphrase on the controlling terminal" do
      allow(strategy).to receive(:fetching?).and_return(true)
      key = mktmpdir/"id_ed25519"
      SystemCommand.run!("ssh-keygen", args: ["-q", "-t", "ed25519", "-N", "test-passphrase", "-f", key])

      PTY.spawn(strategy.env, "ssh-keygen", "-y", "-f", key.to_s) do |_reader, _writer, pid|
        expect(Timeout.timeout(5) { Process.wait2(pid)&.last }).to have_attributes(success?: false)
      ensure
        begin
          Process.kill("KILL", pid)
        rescue Errno::ESRCH
          nil
        end
      end
    end

    it "does not restore credentials during local inspection" do
      ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"

      expect(strategy.env).to eq("GIT_TERMINAL_PROMPT" => "0")
    end
  end

  describe "download credentials" do
    subject(:strategy) do
      Class.new(described_class) do
        T.bind(self, T.class_of(GitDownloadStrategy))
        public :command!, :local_git_env
      end.new(url, name, version)
    end

    let(:home) { mktmpdir }

    before do
      allow(Sandbox).to receive(:isolate_operation?).and_return(true)
      allow(Dir).to receive(:home).with(ENV.fetch("USER")).and_return(home.to_s)
      allow(strategy).to receive(:fetching?).and_return(true)
      allow(strategy).to receive(:command_sandbox).and_wrap_original do |original|
        original.call.tap do |sandbox|
          # Exercise environment filtering without nesting the platform sandbox.
          allow(sandbox).to receive(:sandbox_command) { |args, _tmpdir| args }
          allow(sandbox).to receive(:apply_before_exec?).and_return(false)
        end
      end
      strategy.quiet!
    end

    it "can read identities from an SSH agent" do
      key = home/"id_ed25519"
      SystemCommand.run!("ssh-keygen", args: ["-q", "-t", "ed25519", "-N", "", "-f", key])
      ENV["SSH_AUTH_SOCK"] = (home/"agent.sock").to_s
      agent = Process.spawn("ssh-agent", "-D", "-a", ENV.fetch("SSH_AUTH_SOCK"), out: File::NULL, err: File::NULL)
      Timeout.timeout(5) { sleep 0.01 until File.socket?(ENV.fetch("SSH_AUTH_SOCK")) }
      SystemCommand.run!("ssh-add", args: [key], print_stderr: false)

      expect(strategy.command!("ssh-add", args: ["-L"]).stdout).to eq(Pathname("#{key}.pub").read)
    ensure
      if agent
        Process.kill("TERM", agent)
        Process.wait(agent)
      end
    end

    context "with the gh credential helper" do
      include Test::Helper::Dependencies

      before do
        ensure_test_dependency!(which("gh", ORIGINAL_PATHS), "gh is required.")
        %w[GH_TOKEN GITHUB_TOKEN GH_CONFIG_DIR XDG_CONFIG_HOME HOMEBREW_GITHUB_API_TOKEN].each { ENV.delete(it) }
        ENV["GIT_CONFIG_NOSYSTEM"] = "1"
        ENV["HOMEBREW_GIT"] = Utils::Git.path
        ENV["GIT_CONFIG_GLOBAL"] = (home/".gitconfig").to_s
        (home/".gitconfig").write <<~EOS
          [credential "https://github.com"]
            helper =
            helper = !gh auth git-credential
        EOS
        (home/".config/gh").mkpath
        (home/".config/gh/hosts.yml").write <<~EOS
          github.com:
            user: homebrew-test
            oauth_token: stored-test-token
            git_protocol: https
        EOS
      end

      it "can obtain an existing file-backed gh credential over HTTPS" do
        expect(strategy.command!("git", args:  ["credential", "fill"],
                                        input: "url=#{url}\n\n").stdout)
          .to include("username=homebrew-test\npassword=stored-test-token\n")
      end

      it "passes the GitHub API token to gh during downloads" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"

        expect(strategy.command!("git", args:  ["credential", "fill"],
                                        input: "url=#{url}\n\n").stdout)
          .to include("username=x-access-token\npassword=download-test-token\n")
      end

      it "does not pass a token when gh is absent from the original PATH" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"
        stub_const("ORIGINAL_PATHS", [])

        expect(strategy.command!(RbConfig.ruby, args: ["-e", "puts ENV.key?('GH_TOKEN')"]).stdout).to eq("false\n")
      end

      it "does not pass a token without a matching credential helper" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"
        (home/".gitconfig").write("[credential \"https://example.com\"]\n  helper = !gh auth git-credential\n")

        expect(strategy.command!(RbConfig.ruby, args: ["-e", "puts ENV.key?('GH_TOKEN')"]).stdout).to eq("false\n")
      end

      it "does not pass a token after the credential helpers are reset" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"
        (home/".gitconfig").open("a") { |file| file.puts "  helper =" }

        expect(strategy.command!(RbConfig.ruby, args: ["-e", "puts ENV.key?('GH_TOKEN')"]).stdout).to eq("false\n")
      end

      it "finds gh on the original PATH through a wrapper helper after URL rewriting" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"
        (home/"credential-wrapper").write("#!/bin/sh\nexec gh auth git-credential \"$@\"\n")
        (home/"credential-wrapper").chmod(0755)
        (home/".gitconfig").write <<~EOS
          [url "https://github.com/"]
            insteadOf = https://example.com/
          [credential "https://github.com"]
            helper = #{home}/credential-wrapper
        EOS
        ENV["PATH"] = "/usr/bin:/bin"
        allow(Sandbox).to receive(:isolate_operation?).and_return(false)
        allow(strategy).to receive_messages(url: "https://example.com/homebrew/foo", command_sandbox: nil)

        expect(strategy.command!("git", args: ["credential", "fill"], input: "url=#{url}\n\n").stdout)
          .to include("username=x-access-token\npassword=download-test-token\n")
      end

      it "does not pass the download token to local Git inspection during a fetch" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"

        expect(strategy.local_git_env).not_to have_key("GH_TOKEN")
      end

      it "keeps unrelated tokens out of download commands" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "api-test-token"
        ENV["HOMEBREW_UNRELATED_TOKEN"] = "unrelated-test-token"

        expect(strategy.command!(RbConfig.ruby, args: ["-e", "puts ENV.keys.grep(/TOKEN/).sort"]).stdout)
          .to eq("GH_TOKEN\n")
      end
    end
  end

  describe "#ref?" do
    it "terminates options before the ref" do
      expect(strategy).to receive(:silent_command)
        .with(
          "git",
          args: ["--git-dir", cached_location/".git", "rev-parse", "-q", "--verify", "--end-of-options",
                 "master^{commit}"],
        )
        .and_return(instance_double(SystemCommand::Result, success?: true))

      strategy.ref?
    end
  end

  def git_commit_all
    system "git", "add", "--all"
    # Allow instance variables here to have nice commit messages.
    # rubocop:disable RSpec/InstanceVariable
    system "git", "commit", "-m", "commit number #{@commit_id}"
    @commit_id += 1
    # rubocop:enable RSpec/InstanceVariable
  end

  def setup_git_repo
    system "git", "-c", "init.defaultBranch=master", "init"
    system "git", "remote", "add", "origin", "https://github.com/Homebrew/homebrew-foo"
    FileUtils.touch "README"
    git_commit_all
  end

  describe "#source_modified_time" do
    it "returns the right modification time" do
      cached_location.cd do
        setup_git_repo
      end
      expect(strategy.source_modified_time.to_i).to eq(1_485_115_153)
    end

    it "nulls the global Git config so sandboxed staging reads do not fail" do
      expect(strategy).to receive(:system_command)
        .with(
          "git",
          args:         ["--git-dir", cached_location/".git", "show", "-s", "--format=%cD"],
          env:          { "GIT_TERMINAL_PROMPT" => "0", "GIT_CONFIG_GLOBAL" => File::NULL },
          print_stderr: false,
        )
        .and_return(instance_double(SystemCommand::Result, success?: true,
                                                           stdout:   "Fri, 12 Jun 2026 06:12:11 -0700"))

      expect(strategy.source_modified_time).to eq(Time.parse("Fri, 12 Jun 2026 06:12:11 -0700"))
    end

    it "raises the underlying Git error instead of a Time parsing error on failure" do
      allow(strategy).to receive(:system_command)
        .and_return(instance_double(SystemCommand::Result, success?: false,
                                                           stdout: "", stderr: "fatal: unable to access"))

      expect { strategy.source_modified_time }.to raise_error(/fatal: unable to access/)
    end
  end

  describe "#last_commit" do
    specify "returns the short hash of the last commit" do
      cached_location.cd do
        setup_git_repo
        FileUtils.touch "LICENSE"
        git_commit_all
      end
      expect(strategy.last_commit).to eq("f68266e")
    end

    it "nulls the global Git config so sandboxed staging reads do not fail" do
      expect(strategy).to receive(:system_command)
        .with(
          "git",
          args:         ["--git-dir", cached_location/".git", "rev-parse", "--short=7", "HEAD"],
          env:          { "GIT_TERMINAL_PROMPT" => "0", "GIT_CONFIG_GLOBAL" => File::NULL },
          print_stderr: false,
        )
        .and_return(instance_double(SystemCommand::Result, stdout: "f68266e\n"))

      expect(strategy.last_commit).to eq("f68266e")
    end
  end

  describe "#fetch_last_commit" do
    let(:url) { "file://#{remote_repo}" }
    let(:version) { Version.new("HEAD") }
    let(:remote_repo) { HOMEBREW_PREFIX/"remote_repo" }

    before { remote_repo.mkpath }

    after { FileUtils.rm_rf remote_repo }

    it "fetches the hash of the last commit" do
      remote_repo.cd do
        setup_git_repo
        FileUtils.touch "LICENSE"
        git_commit_all
      end

      expect(strategy.fetch_last_commit).to eq("f68266e")
    end
  end
end
