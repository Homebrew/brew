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
    subject(:strategy) do
      Class.new(described_class) do
        T.bind(self, T.class_of(GitDownloadStrategy))
        public :global_git_config_rules
      end.new(url, name, version)
    end

    let(:home) { mktmpdir }
    let(:allowed_config_paths) do
      strategy.command_sandbox.profile.rules.filter_map do |rule|
        rule.filter&.path if rule.allow && rule.operation == "file-read*" && rule.filter&.type == :literal
      end.uniq
    end

    before do
      ENV.delete("GIT_CONFIG_GLOBAL")
      ENV.delete("XDG_CONFIG_HOME")
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

    it "does not probe configuration when no global Git configuration exists" do
      expect(SystemCommand).not_to receive(:run)

      strategy.command_sandbox
    end

    it "does not probe plain, empty or binary configuration without include tokens" do
      (home/".gitconfig").binwrite("[user]\nname = Example\n\xff\x00".b)
      (home/".config/git").mkpath
      (home/".config/git/config").write("")
      expect(SystemCommand).not_to receive(:run)

      expect(allowed_config_paths).to contain_exactly((home/".gitconfig").to_s,
                                                      (home/".config/git/config").to_s)
    end

    it "allows relative, transitive and empty Git includes without allowing their directory" do
      directory = home/"Dropbox/dotfiles"
      directory.mkpath
      (home/".gitconfig").write("[include]\npath = #{directory}/main\n")
      (directory/"main").write("[include]\npath = nested\n")
      (directory/"nested").write("[include]\npath = empty\n")
      (directory/"empty").write("")

      expect(allowed_config_paths).to contain_exactly(
        (home/".gitconfig").to_s, (directory/"main").to_s,
        (directory/"nested").to_s, (directory/"empty").to_s
      )
    end

    it "expands aliased contexts once and emits one supplemental rule per file" do
      aliases = (1..12).map do |index|
        (home/"alias-#{index}").make_symlink(home)
        "path = alias-#{index}/shared\n"
      end
      (home/".gitconfig").write("[include]\n#{aliases.join}")
      (home/"shared").write("[include]\npath = leaf\n")
      (home/"leaf").write("")
      expect(SystemCommand).to receive(:run).exactly(4).times.and_call_original

      expect(strategy.global_git_config_rules.profile.rules.map { |rule| rule.filter&.path }).to eq(
        %w[.gitconfig shared leaf].map { |path| (home/path).to_s },
      )
    end

    it "expands the same canonical file beside each distinct lexical parent" do
      (home/"shared").write("[include]\npath = leaf\n")
      %w[first second].each do |parent|
        (home/parent).mkpath
        (home/parent/"config").make_symlink(home/"shared")
        (home/parent/"leaf").write("")
      end
      (home/".gitconfig").write("[include]\npath = first/config\npath = second/config\n")

      expect(strategy.global_git_config_rules.profile.rules.map { |rule| rule.filter&.path }).to eq(
        %w[.gitconfig shared first/leaf second/leaf].map { |path| (home/path).to_s },
      )
    end

    it "uses the shortest depth across both roots before suppressing a visited context" do
      chain = (1..9).map { |index| home/"chain-#{index}" }
      (home/".gitconfig").write("[include]\npath = #{chain.first}\n")
      [*chain, home/"shared"].each_cons(2) { |parent, child| parent.write("[include]\npath = #{child}\n") }
      (home/"shared").write("[include]\npath = leaf\n")
      (home/"leaf").write("")
      (home/".config/git").mkpath
      (home/".config/git/config").write("[include]\npath = #{home}/shared\n")

      expect(allowed_config_paths).to include((home/"leaf").to_s)
    end

    it "replays compiled literal rules without resolving a replaced symlink again" do
      (home/".gitconfig").write("[include]\npath = target\n")
      (home/"target").write("")
      strategy.command_sandbox
      (home/"target").unlink
      (home/"replacement").write("")
      (home/"target").make_symlink(home/"replacement")

      expect(allowed_config_paths).to contain_exactly((home/".gitconfig").to_s, (home/"target").to_s)
    end

    it "freezes the supplemental builder, rules and filters" do
      (home/".gitconfig").write("")
      rules = strategy.global_git_config_rules

      expect([rules, rules.profile, rules.profile.rules, *rules.profile.rules,
              *rules.profile.rules.filter_map(&:filter),
              *rules.profile.rules.filter_map { |rule| rule.filter&.path }]).to all(be_frozen)
    end

    test_each([false, true]) do |failure|
      it "builds once per actual fetch and resets after #{failure ? "failure" : "success"}" do
        (home/".gitconfig").write("[include]\npath = first\n")
        (home/"first").write("")
        (home/"second").write("")
        allow(strategy).to receive(:repo_valid?).and_return(true)
        plans = []
        allow(strategy).to receive(:update) do
          plans << strategy.command_sandbox.profile.rules.filter_map { |rule| rule.filter&.path }
          (home/".gitconfig").atomic_write("[include]\npath = second\n")
          plans << strategy.command_sandbox.profile.rules.filter_map { |rule| rule.filter&.path }
          raise "fetch failed" if failure && plans.length == 2
        end
        expect(strategy).to receive(:global_git_config_rules).twice.and_call_original
        if failure
          expect { strategy.fetch }.to raise_error("fetch failed")
        else
          strategy.fetch
        end
        strategy.fetch

        expect(plans.map { |plan| plan.grep(%r{/(first|second)$}) }).to eq(
          [[(home/"first").to_s], [(home/"first").to_s], [(home/"second").to_s], [(home/"second").to_s]],
        )
      end
    end

    it "caches an empty discovery result until the next fetch" do
      allow(strategy).to receive(:repo_valid?).and_return(true)
      plans = []
      allow(strategy).to receive(:update) do
        plans << strategy.command_sandbox.profile.rules.count { |rule| rule.allow && rule.filter&.type == :literal }
        (home/".gitconfig").atomic_write("")
        plans << strategy.command_sandbox.profile.rules.count { |rule| rule.allow && rule.filter&.type == :literal }
      end
      expect(strategy).to receive(:global_git_config_rules).twice.and_call_original
      strategy.fetch
      strategy.fetch

      expect(plans).to eq([0, 0, 1, 1])
    end

    it "clears compiled permissions immediately after a failed fetch" do
      (home/".gitconfig").write("[include]\npath = first\n")
      (home/"first").write("")
      (home/"second").write("")
      allow(strategy).to receive(:repo_valid?).and_return(true)
      allow(strategy).to receive(:update) do
        strategy.command_sandbox
        raise "fetch failed"
      end
      expect { strategy.fetch }.to raise_error("fetch failed")
      (home/".gitconfig").atomic_write("[include]\npath = second\n")

      expect(allowed_config_paths).to contain_exactly((home/".gitconfig").to_s, (home/"second").to_s)
    end

    it "retains discovered files and both roots when the shared work budget is exhausted" do
      (home/".gitconfig").write("[include]\npath = first\n")
      (home/"first").write("[include]\npath = second\n")
      (home/"second").write("")
      (home/".config/git").mkpath
      (home/".config/git/config").write("")
      stub_const("GitDownloadStrategy::MAXIMUM_CONFIG_DISCOVERY_WORK", 7)
      expect(strategy).to receive(:opoo).once.with(/work limit reached/)
      first = allowed_config_paths
      second = strategy.command_sandbox.profile.rules.filter_map do |rule|
        rule.filter&.path if rule.allow && rule.operation == "file-read*" && rule.filter&.type == :literal
      end

      expect([first, second]).to all(contain_exactly((home/".gitconfig").to_s,
                                                     (home/".config/git/config").to_s, (home/"first").to_s))
    end

    it "bounds prefilter reads by the remaining byte budget" do
      (home/".gitconfig").write("x" * 20)
      stub_const("GitDownloadStrategy::MAXIMUM_CONFIG_DISCOVERY_BYTES", 8)
      expect(File).to receive(:binread).with(home/".gitconfig", 9).and_call_original
      expect(SystemCommand).not_to receive(:run)
      expect(strategy).to receive(:opoo).once.with(/byte limit reached/)

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s])
    end

    it "charges duplicate include records before visiting their targets" do
      (home/".gitconfig").write("[include]\n#{"path = missing\n" * 20}")
      stub_const("GitDownloadStrategy::MAXIMUM_CONFIG_DISCOVERY_WORK", 8)
      expect(SystemCommand).to receive(:run).twice.and_call_original
      expect(strategy).to receive(:opoo).once.with(/work limit reached/)

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s])
    end

    it "charges missing path attempts to the same work budget" do
      (home/".gitconfig").write("[include]\npath = missing\npath = leaf\n")
      (home/"leaf").write("")
      stub_const("GitDownloadStrategy::MAXIMUM_CONFIG_DISCOVERY_WORK", 8)
      expect(strategy).to receive(:opoo).once.with(/work limit reached/)

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s])
    end

    it "charges native query output to the aggregate byte budget" do
      config = "[include]\npath = leaf\n"
      (home/".gitconfig").write(config)
      (home/"leaf").write("")
      stub_const("GitDownloadStrategy::MAXIMUM_CONFIG_DISCOVERY_BYTES", config.bytesize + 5)
      expect(SystemCommand).to receive(:run).once.and_call_original
      expect(strategy).to receive(:opoo).once.with(/byte limit reached/)

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s])
    end

    it "retains exact rules and caches the partial result after a native timeout" do
      (home/".gitconfig").write("[include]\npath = leaf\n")
      expect(SystemCommand).to receive(:run).once.with("git", hash_including(timeout: be_between(0, 2)))
                                            .and_raise(Timeout::Error)
      expect(strategy).to receive(:opoo).once.with(/query timed out/)
      strategy.command_sandbox

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s])
    end

    it "stops before a native probe when the monotonic deadline has elapsed" do
      (home/".gitconfig").write("[include]\npath = leaf\n")
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(0.0, 3.0)
      expect(SystemCommand).not_to receive(:run)
      expect(strategy).to receive(:opoo).once.with(/time limit reached/)

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s])
    end

    it "falls back to Git when the binary prefilter read fails" do
      (home/".gitconfig").write("[include]\npath = leaf\n")
      (home/"leaf").write("")
      allow(File).to receive(:binread).and_call_original
      allow(File).to receive(:binread).with(home/".gitconfig", anything).and_raise(Errno::EACCES)

      expect(allowed_config_paths).to contain_exactly((home/".gitconfig").to_s, (home/"leaf").to_s)
    end

    it "does not open a FIFO named as an include target" do
      (home/".gitconfig").write("[include]\npath = pipe\n")
      File.mkfifo(home/"pipe")
      expect(File).not_to receive(:binread).with(home/"pipe", anything)

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s])
    end

    it "neutralises runtime configuration injections only for native discovery" do
      (home/".gitconfig").write("[include]\npath = leaf\n")
      (home/"leaf").write("")
      ENV["GIT_CONFIG_COUNT"] = "invalid"
      ENV["GIT_CONFIG_PARAMETERS"] = "invalid"

      expect(paths: allowed_config_paths, count: ENV.fetch("GIT_CONFIG_COUNT"),
             parameters: ENV.fetch("GIT_CONFIG_PARAMETERS")).to eq(
               paths: [(home/".gitconfig").to_s, (home/"leaf").to_s], count: "invalid", parameters: "invalid",
             )
    end

    it "does not discover default roots when the explicit global path is empty" do
      (home/".gitconfig").write("[include]\npath = leaf\n")
      ENV["GIT_CONFIG_GLOBAL"] = ""
      expect(SystemCommand).not_to receive(:run)

      expect(allowed_config_paths).to be_empty
    end

    it "resolves includes beside a symlink's lexical path and expands tilde paths" do
      directory = home/"Dropbox/dotfiles"
      directory.mkpath
      (directory/"root").write("[include]\npath = relative\npath = ~/Dropbox/dotfiles/tilde\n")
      (home/".gitconfig").make_symlink(directory/"root")
      (home/"relative").write("")
      (directory/"relative").write("")
      (directory/"tilde").write("")

      expect(allowed_config_paths).to contain_exactly(
        (directory/"root").to_s, (home/"relative").to_s, (directory/"tilde").to_s
      )
    end

    it "resolves parent components after directory symlinks" do
      directory = home/"Dropbox/dotfiles"
      (directory/"nested").mkpath
      (home/"link").make_symlink(directory/"nested")
      (home/".gitconfig").write("[include]\npath = link/main\n")
      (directory/"nested/main").write("[include]\npath = ../leaf\n")
      (directory/"leaf").write("")
      (home/"leaf").write("")

      expect(allowed_config_paths).to contain_exactly(
        (home/".gitconfig").to_s, (directory/"nested/main").to_s, (directory/"leaf").to_s
      )
    end

    it "preserves whitespace-only include filenames" do
      (home/".gitconfig").write("[include]\npath = \" \"\n")
      (home/" ").write("")

      expect(allowed_config_paths).to contain_exactly((home/".gitconfig").to_s, (home/" ").to_s)
    end

    it "follows conditional includes before the cached repository exists" do
      FileUtils.rmdir cached_location
      directory = home/"Dropbox/dotfiles"
      directory.mkpath
      (home/".gitconfig").write("[includeIf \"gitdir:#{cached_location}/\"]\npath = #{directory}/main\n")
      (directory/"main").write("[includeIf \"onbranch:main\"]\npath = empty\n")
      (directory/"empty").write("")

      expect(paths: allowed_config_paths, cache_created: cached_location.exist?).to eq(
        paths:         [(home/".gitconfig").to_s, (directory/"main").to_s, (directory/"empty").to_s],
        cache_created: false,
      )
    end

    test_each([".config/git/config", "custom-xdg/git/config", "empty-xdg"]) do |config_path|
      it "follows includes from #{config_path}" do
        ENV["XDG_CONFIG_HOME"] = (home/"custom-xdg").to_s if config_path.start_with?("custom-xdg")
        ENV["XDG_CONFIG_HOME"] = "" if config_path == "empty-xdg"
        config = home/((config_path == "empty-xdg") ? ".config/git/config" : config_path)
        config.dirname.mkpath
        config.write("[include]\npath = included\n")
        (config.dirname/"included").write("")

        expect(allowed_config_paths).to contain_exactly(config.to_s, (config.dirname/"included").to_s)
      end
    end

    it "uses an explicit global configuration instead of the default files" do
      config = home/"custom-global"
      config.write("[include]\npath = included\n")
      (home/"included").write("")
      (home/".gitconfig").write("[include]\npath = unrelated\n")
      (home/"unrelated").write("")
      ENV["GIT_CONFIG_GLOBAL"] = config.to_s

      expect(allowed_config_paths).to contain_exactly(config.to_s, (home/"included").to_s)
    end

    it "ignores missing, directory and malformed inactive targets without failing the download" do
      (home/"directory").mkpath
      (home/"invalid").write("[invalid\n")
      (home/".gitconfig").write <<~EOS
        [includeIf "onbranch:unused"]
          path = missing
          path = directory
          path = invalid
      EOS

      expect(allowed_config_paths).to contain_exactly((home/".gitconfig").to_s, (home/"invalid").to_s)
    end

    it "keeps valid includes when an inactive condition has an unexpandable path" do
      (home/".gitconfig").write <<~EOS
        [include]
          path = included
        [includeIf "onbranch:unused"]
          path = ~homebrew-nonexistent-include-user/config
      EOS
      (home/"included").write("")

      expect(allowed_config_paths).to contain_exactly((home/".gitconfig").to_s, (home/"included").to_s)
    end

    it "does not use repository configuration to grant additional reads" do
      (cached_location/".git").mkpath
      (cached_location/".git/config").write("[include]\npath = #{home}/unrelated\n")
      (home/"unrelated").write("")

      expect(allowed_config_paths).to be_empty
    end

    it "does not grant config reads during local repository inspection" do
      (home/".gitconfig").write("[include]\npath = included\n")
      (home/"included").write("")
      allow(strategy).to receive(:fetching?).and_return(false)

      expect(allowed_config_paths).to be_empty
    end

    it "bounds cycles whose lexical paths grow through a directory symlink" do
      (home/"loop").make_symlink(home)
      (home/".gitconfig").write("[include]\npath = loop/.gitconfig\n")
      expect(SystemCommand).to receive(:run).at_most(20).times.and_call_original

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s])
    end

    it "does not grant reads beyond Git's ten-level include limit" do
      includes = (1..11).map { |depth| home/"include-#{depth}" }
      (home/".gitconfig").write("[include]\npath = #{includes.first}\n")
      includes.each_cons(2) { |parent, child| parent.write("[include]\npath = #{child}\n") }
      includes.last.write("")

      expect(allowed_config_paths).to eq([(home/".gitconfig").to_s, *includes.first(10).map(&:to_s)])
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
