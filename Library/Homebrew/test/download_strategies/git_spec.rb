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
    it "disables submodule recursion and terminates options before the URL" do
      expect(strategy.clone_args).to start_with("clone", "--no-recurse-submodules")
        .and end_with("--end-of-options", url, cached_location.to_s)
    end
  end

  describe "tool selection after a failed download" do
    subject(:strategy) do
      Class.new(described_class) do
        T.bind(self, T.class_of(GitDownloadStrategy))
        public :git_download_command!
      end.new(url, name, version)
    end

    let(:selection_cache) { HOMEBREW_CACHE/"tool-selection/git" }
    let(:error) { ErrorDuringExecution.new(["git", "fetch"], status: 128) }

    before do
      selection_cache.dirname.mkpath
      selection_cache.write "cached selection"
      allow(strategy).to receive(:env).and_return({})
      allow(strategy).to receive(:system_command!).and_raise(error)
    end

    it "preserves the selection and original download error" do
      expect { strategy.git_download_command!(args: ["fetch"]) }
        .to raise_error(error) { expect(selection_cache).to exist }
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
        public :command!, :env, :local_git_env
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

        expect(strategy.command!("git", args:  ["credential", "fill"], env: strategy.env(credential_lookup: true),
                                        input: "url=#{url}\n\n").stdout)
          .to include("username=x-access-token\npassword=download-test-token\n")
      end

      it "does not pass a token when gh is absent from the original PATH" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"
        stub_const("ORIGINAL_PATHS", [])

        expect(strategy.env(credential_lookup: true)).not_to have_key("GH_TOKEN")
      end

      it "does not pass a token without a matching credential helper" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"
        (home/".gitconfig").write("[credential \"https://example.com\"]\n  helper = !gh auth git-credential\n")

        expect(strategy.env(credential_lookup: true)).not_to have_key("GH_TOKEN")
      end

      it "does not pass a token after the credential helpers are reset" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"
        (home/".gitconfig").open("a") { |file| file.puts "  helper =" }

        expect(strategy.env(credential_lookup: true)).not_to have_key("GH_TOKEN")
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

        expect(strategy.command!("git", args: ["credential", "fill"], input: "url=#{url}\n\n",
                                       env: strategy.env(credential_lookup: true)).stdout)
          .to include("username=x-access-token\npassword=download-test-token\n")
      end

      it "does not pass the download token to local Git inspection during a fetch" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "download-test-token"

        expect(strategy.local_git_env).not_to have_key("GH_TOKEN")
      end

      it "keeps unrelated tokens out of download commands" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = "api-test-token"
        ENV["HOMEBREW_UNRELATED_TOKEN"] = "unrelated-test-token"

        expect(strategy.command!(RbConfig.ruby, args: ["-e", "puts ENV.keys.grep(/TOKEN/).sort"],
                                                env:  strategy.env(credential_lookup: true)).stdout)
          .to eq("GH_TOKEN\n")
      end
    end
  end

  describe "Keychain credential handoff" do
    let(:resolved_url) { url }
    let(:helper) { "!gh auth git-credential\n" }
    let(:git_result) { instance_double(SystemCommand::Result, success?: true, stdout: "") }

    before do
      allow(Sandbox).to receive(:isolate_operation?).and_return(true)
      ENV.delete("HOMEBREW_GITHUB_API_TOKEN")
      ENV.delete("GH_TOKEN")
      allow(Utils::Git).to receive(:ensure_installed!)
      allow(strategy).to receive_messages(repo_valid?: false, submodules?: false)
      allow(strategy).to receive(:which).with("gh", ORIGINAL_PATHS).and_return(Pathname("/trusted/bin/gh"))
      allow(strategy).to receive_messages(system_command!: git_result, system_command: git_result)
      allow(strategy).to receive(:system_command)
        .with("git", hash_including(args: ["ls-remote", "--get-url", "--", url]))
        .and_return(instance_double(SystemCommand::Result, success?: true, stdout: "#{resolved_url}\n"))
      allow(strategy).to receive(:system_command)
        .with("git", hash_including(args: ["config", "--get-urlmatch", "credential.helper", resolved_url]))
        .and_return(instance_double(SystemCommand::Result, success?: true, stdout: helper))
      allow(GitHub::API).to receive(:github_cli_token).and_return("keychain-test-token")
      strategy.quiet!
    end

    it "passes the selected credential to the clone and registers it for redaction" do
      expect(strategy).to receive(:system_command!).with(
        "git", hash_including(args: strategy.clone_args, env: hash_including("GH_TOKEN" => "keychain-test-token"),
                              secrets: ["keychain-test-token"])
      ).and_return(git_result)

      strategy.fetch
    end

    it "keeps the credential out of formula evaluation while launching Git" do
      visible_tokens = []
      allow(strategy).to receive(:system_command!)
        .with("git", hash_including(args: strategy.clone_args)) do
          visible_tokens << Formulary.load_formula(
            "download-token", mktmpdir/"download-token.rb",
            <<~RUBY,
              class DownloadToken < Formula
                desc ENV.values_at("HOMEBREW_GITHUB_API_TOKEN", "GH_TOKEN").compact.join
                url "https://example.com/download-token-1.0.tar.gz"
              end
            RUBY
            "DownloadTokenNamespace", flags: [], ignore_errors: false
          ).desc
          git_result
        end

      strategy.fetch

      expect(visible_tokens).to eq([""])
    end

    test_each([nil, "explicit-test-token"].product(%w[checkout reset config submodule])) do |(token, command)|
      it "keeps the token out of #{command} commands (explicit token: #{token.present?})" do
        ENV["HOMEBREW_GITHUB_API_TOKEN"] = token
        allow(strategy).to receive_messages(repo_valid?: true, partial_clone_sparse_checkout?: true,
                                            submodules?: true)
        expect(strategy).not_to receive(:system_command!)
          .with("git", hash_including(args: array_including(command), env: hash_including("GH_TOKEN")))

        strategy.fetch
      end
    end

    test_each([false, true]) do |shallow|
      it "passes the credential when updating a cached repository (shallow: #{shallow})" do
        allow(strategy).to receive_messages(repo_valid?: true, shallow_dir?: shallow)
        expect(strategy).to receive(:system_command!).with(
          "git", hash_including(args: ["fetch", "--no-recurse-submodules", "origin", *("--unshallow" if shallow)],
                                env:  hash_including("GH_TOKEN" => "keychain-test-token"))
        ).and_return(git_result)

        strategy.fetch
      end
    end

    it "retrieves the credential only for the top-level clone when submodules are present" do
      allow(strategy).to receive(:submodules?).and_return(true)
      expect(GitHub::API).to receive(:github_cli_token).once.and_return("keychain-test-token")

      strategy.fetch
    end

    it "does not retrieve credentials for local revision inspections" do
      expect(GitHub::API).not_to receive(:github_cli_token)

      strategy.last_commit
    end

    it "uses the selected gh executable with a bounded lookup" do
      expect(GitHub::API).to receive(:github_cli_token)
        .with(executable: Pathname("/trusted/bin/gh"), timeout: 10)
        .once
        .and_return("keychain-test-token")

      strategy.fetch
    end

    it "preserves an explicitly supplied token" do
      ENV["HOMEBREW_GITHUB_API_TOKEN"] = "explicit-test-token"
      expect(GitHub::API).not_to receive(:github_cli_token)

      strategy.fetch
    end

    it "does not retrieve credentials when gh is unavailable" do
      allow(strategy).to receive(:which).with("gh", ORIGINAL_PATHS).and_return(nil)
      expect(GitHub::API).not_to receive(:github_cli_token)

      strategy.fetch
    end

    it "does not retrieve credentials when the download is not sandboxed" do
      allow(Sandbox).to receive(:isolate_operation?).and_return(false)
      expect(GitHub::API).not_to receive(:github_cli_token)

      strategy.fetch
    end

    it "continues with the configured helper when credential retrieval times out" do
      allow(GitHub::API).to receive(:github_cli_token).and_raise(Timeout::Error)
      expect(strategy).to receive(:system_command!)
        .with("git", hash_including(args: strategy.clone_args, env: hash_excluding("GH_TOKEN")))
        .and_return(git_result)

      strategy.fetch
    end

    it "continues with the configured helper when no credential is available" do
      allow(GitHub::API).to receive(:github_cli_token).and_return(nil)
      expect(strategy).to receive(:system_command!)
        .with("git", hash_including(args: strategy.clone_args, env: hash_excluding("GH_TOKEN")))
        .and_return(git_result)

      strategy.fetch
    end

    context "with a GitHub-specific strategy" do
      subject(:strategy) { GitHubGitDownloadStrategy.new(url, name, version) }

      it "passes the credential to its clone" do
        expect(strategy).to receive(:system_command!)
          .with("git", hash_including(args: strategy.clone_args,
                                      env:  hash_including("GH_TOKEN" => "keychain-test-token")))
          .and_return(git_result)

        strategy.fetch
      end
    end

    context "with a custom strategy" do
      subject(:strategy) { Class.new(described_class).new(url, name, version) }

      it "does not retrieve credentials" do
        expect(GitHub::API).not_to receive(:github_cli_token)

        strategy.fetch
      end
    end

    context "with a URL rewritten to GitHub" do
      let(:url) { "https://example.com/homebrew/foo" }
      let(:resolved_url) { "https://github.com/homebrew/foo" }

      it "uses the effective URL to select credentials" do
        expect(GitHub::API).to receive(:github_cli_token).and_return("keychain-test-token")

        strategy.fetch
      end
    end

    context "with a wrapper helper" do
      let(:helper) { "!/custom/wrapper\n" }

      it "uses the existing token lookup without parsing the helper command" do
        expect(GitHub::API).to receive(:github_cli_token).and_return("keychain-test-token")

        strategy.fetch
      end
    end

    test_each(%w[https://example.com/homebrew/foo https://github.com.example.com/homebrew/foo
                 https://github.com@example.com/homebrew/foo https://github.com:8443/homebrew/foo
                 http://github.com/homebrew/foo git@github.com:homebrew/foo.git file:///repo.git]) do |remote_url|
      context "when the URL resolves to #{remote_url}" do
        let(:resolved_url) { remote_url }

        it "does not retrieve GitHub credentials" do
          expect(GitHub::API).not_to receive(:github_cli_token)

          strategy.fetch
        end
      end
    end

    test_each(["", "!gh auth git-credential\n\n"]) do |configured_helper|
      context "with helper #{configured_helper.inspect}" do
        let(:helper) { configured_helper }

        it "does not retrieve credentials without an enabled helper" do
          expect(GitHub::API).not_to receive(:github_cli_token)

          strategy.fetch
        end
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

    it "does not fetch submodules even when repository configuration enables recursion" do
      ENV["GIT_ALLOW_PROTOCOL"] = "file"
      remote_repo.cd do
        setup_git_repo
        SystemCommand.run!("git", args: ["submodule", "add", remote_repo, "child"])
        git_commit_all
      end
      revision = strategy.fetch_last_commit
      SystemCommand.run!("git", args: ["-C", cached_location, "config", "submodule.recurse", "true"])
      SystemCommand.run!("git", args: ["-C", cached_location, "config", "fetch.recurseSubmodules", "true"])
      SystemCommand.run!("git",
                         args: ["-C", cached_location, "config", "submodule.child.fetchRecurseSubmodules", "true"])
      SystemCommand.run!("git",
                         args: ["-C", cached_location/"child", "remote", "set-url", "origin", "/missing-submodule"])
      allow(strategy).to receive(:submodules?).and_return(false)

      expect(strategy.fetch_last_commit).to eq(revision)
    end
  end
end
