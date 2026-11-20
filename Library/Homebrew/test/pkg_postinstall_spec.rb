# typed: strict
# frozen_string_literal: true

require "open3"
require "socket"

RSpec.describe "package postinstall", type: :system do
  # Keep each Sorbet signature with its let declaration.
  # rubocop:disable RSpec/ScatteredLet
  sig { returns(Pathname) }
  let(:test_root) { mktmpdir }

  sig { returns(Pathname) }
  let(:prefix) { test_root/"prefix" }

  sig { returns(Integer) }
  let(:install_uid) { Process.uid }

  sig { returns(Integer) }
  let(:prefix_uid) { install_uid }

  sig { returns(String) }
  let(:parent_mode) { "drwxr-xr-x" }

  sig { returns(Pathname) }
  let(:payload) { test_root/"db/payload" }

  sig { returns(String) }
  let(:install_groups) { "staff admin" }

  sig { returns(String) }
  let(:primary_group) { "staff" }

  sig { returns(String) }
  let(:initial_umask) { "000" }

  sig { returns(String) }
  let(:child_umask) { "000" }

  sig { returns(T::Boolean) }
  let(:developer_tools) { true }

  sig { returns(T::Boolean) }
  let(:sudo_available) { true }

  sig { returns(Integer) }
  let(:caller_uid) { 0 }

  sig { returns(Integer) }
  let(:git_exit_status) { 0 }

  sig { returns(String) }
  let(:developer_dir) { "#{test_root}/Developer Tools" }

  sig { returns(Pathname) }
  let(:commands) { test_root/"commands" }

  sig { returns(T::Hash[String, T.nilable(String)]) }
  let(:git_env) do
    config_env = Utils::Git.no_global_config_env.merge("GIT_CONFIG_NOSYSTEM" => "1")
    Utils.safe_popen_read(config_env, Utils::Git.git, "rev-parse", "--local-env-vars")
         .split.to_h { |name| [name, nil] }.merge(config_env)
  end

  sig { params(script: String).returns([String, String, Process::Status]) }
  def result(script = "postinstall")
    Open3.capture3("/bin/bash", "-c", <<~SH)
      umask #{initial_umask}
      id() {
        if [[ "$#" == 1 && "$1" == -u ]]; then echo #{caller_uid}; return; fi
        case "$1" in
          -Gn) echo "#{install_groups}" ;;
          -gn) echo "#{primary_group}" ;;
          *) echo #{install_uid} ;;
        esac
      }
      stat() {
        case "$2" in
          '%u %Sp') if [[ "$3" == "#{prefix.parent}" ]]; then echo '0 #{parent_mode}'; else echo '0 drwxr-xr-x'; fi ;;
          '%u') echo #{prefix_uid} ;;
          *) return 1 ;;
        esac
      }
      ls() { echo 'drwxr-xr-x 1 root wheel'; }
      pkgutil() {
        case "$1" in --pkgs) echo sh.brew.homebrew ;; --files) echo .git/HEAD ;; *) return 1 ;; esac
      }
      chown() { echo "chown $*" >> "#{commands}"; }
      xcode-select() {
        [[ "#{developer_tools}" == true ]] || return 1
        echo "#{developer_dir}"
      }
      command() {
        if [[ "$*" == "-v sudo" && "#{sudo_available}" == false ]]; then return 1; fi
        builtin command "$@"
      }
      sudo() {
        [[ "#{sudo_available}" == true ]] || return 127
        echo "sudo $*" >> "#{commands}"
        [[ "$1" == -u && "$2" == "##{install_uid}" && "$3" == -- ]] || return 1
        shift 3
        (umask #{child_umask}; "$@")
      }
      login() {
        echo "login $1 $2 $3 $4" >> "#{commands}"
        [[ "$1 $2 $3 $4" == "-f -l -q pkg-user" ]] || return 1
        shift 4
        (umask #{child_umask}; "$@") || true
        return 0
      }
      source "#{test_root}/#{script}" "" / /
    SH
  end
  # rubocop:enable RSpec/ScatteredLet

  sig { params(args: T.any(String, Pathname)).returns(String) }
  def git(*args)
    SystemCommand.run!(Utils::Git.git, args:, env: git_env).stdout.chomp
  end

  sig { void }
  def stage_payload
    (payload/".git").mkpath
    (payload/".git/HEAD").write "ref: refs/heads/stable\n"
    (payload/"cache_api").mkpath
    (payload/"cache_api/formula.json").write "{}"
  end

  before do
    (prefix/"bin").mkpath
    stage_payload
    (test_root/"Developer Tools/usr/bin").mkpath
    (test_root/"Developer Tools/usr/bin/git").write <<~SH
      #!/bin/bash
      if [[ "$*" == *" fetch "* ]]; then echo "fetch ${GIT_ALLOW_PROTOCOL} ${PKG_TEST_INHERITED-unset}" >> "#{commands}"; fi
      if [[ "$*" == *" tag "* ]]; then echo 7.0.3; fi
      if [[ "$*" == *" rev-parse "* ]]; then echo deadbeef; fi
      if [[ "$*" == *" --get core.excludesFile" ]]; then printf 'command\\0%s\\0' "$HOME/.config/git/ignore"; fi
      if [[ "$*" == *" symbolic-ref --quiet refs/heads/stable" ]]; then exit 1; fi
      exit #{git_exit_status}
    SH
    (test_root/"Developer Tools/usr/bin/git").chmod(0755)
    commands.write ""
    (test_root/"paths").binwrite(["040000 Library", "040000 Library/Homebrew", "100755 bin/brew", ""].join("\0"))
    scripts = HOMEBREW_LIBRARY_PATH.parent.parent/"package/scripts"
    [scripts/"preinstall", scripts/"postinstall", HOMEBREW_LIBRARY_PATH/"utils/macos_user.sh"].each do |file|
      script = file.read.gsub("/opt/homebrew", prefix.to_s)
                   .gsub("/private/var/db/sh.brew.homebrew", payload.to_s)
      # The scripts use the host's tools even when `--generic` makes OS.linux? false.
      if OS.kernel_name == "Linux"
        script = script.gsub("mv -h ", "mv ").gsub("rm -rfx", "rm -rf --one-file-system")
                       .gsub("cp -cR", "cp --reflink=auto -R")
      end
      (test_root/file.basename).write(script)
    end
    (test_root/"macos_user.sh").append_lines <<~SH
      homebrew-package-user() { echo pkg-user; }
      homebrew-user-home() { echo "#{test_root}"; }
    SH
  end

  context "when upgrading a package that owned .git" do
    sig { returns(Pathname) }
    let(:origin) { test_root/"origin" }

    sig { params(args: T.any(String, Pathname)).returns(String) }
    def previous_git(*args)
      git "--git-dir", prefix/".homebrew-pkg-previous.git", "--work-tree", prefix, *args
    end

    before do
      (test_root/"Developer Tools/usr/bin").write_exec_script(Utils::Git.path || raise("Git is required"))
      git "init", "-q", "-b", "stable", origin
      (origin/".gitignore").write "/*\n!/Library\n"
      git "-C", origin, "add", "-f", ".gitignore"
      git "-C", origin, "commit", "-qm", "first"
      git "-C", origin, "tag", "1.0.0"
      git "-C", origin, "branch", "retired", git("-C", origin, "commit-tree", "HEAD^{tree}", "-m", "retired")
      git "clone", "-q", "--no-local", origin, test_root/"first"
      FileUtils.mv(test_root/"first/.git", prefix/".git")
      git "-C", prefix, "branch", "local-work", "origin/retired"
      git "-C", prefix, "commit-graph", "write", "--reachable"
      receipt_packs = (prefix/".git/objects/pack").children

      git "-C", origin, "branch", "-D", "retired"
      git "-C", origin, "commit", "-qm", "packaged", "--allow-empty"
      git "-C", origin, "tag", "1.0.1"
      _, stderr, status = result("preinstall")
      raise stderr unless status.success?

      FileUtils.rm_f receipt_packs
      git "clone", "-q", "--no-local", origin, payload
      stage_payload
      # Allow the local origin and the loopback HTTP server used by the fetch tests.
      script = test_root/"postinstall"
      script.write(script.read.sub("GIT_ALLOW_PROTOCOL=https", "GIT_ALLOW_PROTOCOL=file:http"))
    end

    it "preserves local history and fetches the latest release" do
      previous_git "tag", "999.0.0", "local-work"
      previous_git "remote", "set-url", "origin", test_root/"other-origin"
      (prefix/".homebrew-pkg-previous.git/info/attributes").write "bin/brew filter=uppercase\n"
      previous_git "config", "filter.uppercase.smudge", "tr a-z A-Z"
      (origin/"bin").mkpath
      (origin/"bin/brew").write "latest\n"
      git "-C", origin, "add", "-f", "bin/brew"
      git "-C", origin, "commit", "-qm", "latest"
      git "-C", origin, "tag", "-m", "latest release", "1.0.2"
      git "-C", origin, "tag", "26-tahoe", "1.0.0"

      _, stderr, status = result
      expect([status.exitstatus, git("-C", prefix, "describe", "--tags", "--exact-match"),
              git("-C", prefix, "show", "-s", "--format=%s", "local-work"),
              (prefix/"bin/brew").read, git("-C", prefix, "status", "--porcelain", "--untracked-files=no"),
              git("-C", prefix, "fsck", "--no-dangling")])
        .to eq([0, "1.0.2", "retired", "latest\n", "", ""]), stderr
    end

    it "can update from the package offline" do
      git "-C", payload, "tag", "1.0.2", git("-C", payload, "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "later")
      FileUtils.mv(origin, test_root/"offline")

      _, stderr, status = result
      expect([status.exitstatus, git("-C", prefix, "describe", "--tags", "--exact-match"),
              git("-C", prefix, "show", "-s", "--format=%s", "local-work")])
        .to eq([0, "1.0.1", "retired"]), stderr
    end

    it "honours the live repository's excludes when cleaning the upgraded worktree" do
      (prefix/".homebrew-pkg-previous.git/info/exclude").append_lines "settings.local"
      (prefix/"Library").mkpath
      (prefix/"Library/settings.local").write "keep"
      (prefix/"Library/scratch.local").write "clean"

      _, stderr, status = result
      expect([status.exitstatus, prefix.glob("Library/*.local")])
        .to eq([0, [prefix/"Library/settings.local"]]), stderr
    end

    it "removes obsolete commands and keeps local exclusions and backups when replacing Git" do
      cmd = prefix/"Library/Homebrew/cmd"
      cmd.mkpath
      (cmd/"obsolete.rb").write "old command"
      (cmd/"notes.local").write "keep"
      (cmd/"personal.local").write "keep"
      previous_git "add", "-f", cmd/"obsolete.rb"
      previous_git "commit", "-qm", "old command"
      (prefix/".homebrew-pkg-previous.git/info/exclude").append_lines "notes.local"
      (test_root/"gitignore").write "personal.local\n"
      previous_git "config", "core.excludesFile", "~/gitignore"
      (prefix/".homebrew-pkg-previous.git/index.lock").write ""
      # Expose backup directories to git clean, including a previous incomplete backup.
      (origin/".gitignore").append_lines "!/.homebrew-pkg-backup.*/"
      git "-C", origin, "commit", "-qam", "updated ignores"
      git "-C", origin, "tag", "1.0.2"
      old_backup = prefix/".homebrew-pkg-backup.older"
      old_backup.mkpath
      (old_backup/"saved").write "keep"

      _, stderr, status = result
      expect([status.exitstatus, cmd.children.map { |file| file.basename.to_s }.sort, (old_backup/"saved").file?,
              prefix.glob(".homebrew-pkg-backup.*/.git/index.lock").size,
              prefix.glob(".homebrew-pkg-backup.*/live.git/index.lock").size])
        .to eq([0, %w[notes.local personal.local], true, 1, 1]), stderr
      expect(git("-C", cmd, "check-ignore", "notes.local", "personal.local").lines(chomp: true))
        .to eq(%w[notes.local personal.local])
    end

    test_each(%w[.homebrew-pkg-previous.git/info/exclude local.ignore]) do |path|
      it "leaves untracked files in place when it cannot read #{path}" do
        previous_git "config", "core.excludesFile", path if path == "local.ignore"
        (prefix/path).write "notes.local\n"
        (prefix/path).chmod(0000)
        (prefix/".homebrew-pkg-previous.git/index.lock").write ""
        (prefix/"Library").mkpath
        (prefix/"Library/notes.local").write "keep"

        _, stderr, status = result
        expect([status.exitstatus, (prefix/"Library/notes.local").file?, git("-C", prefix, "describe", "--tags")])
          .to eq([0, true, "1.0.1"]), stderr
      end
    end

    it "isolates fixture commits from the caller's Git configuration and index" do
      config = test_root/"git/config"
      config.dirname.mkpath
      config.write "[commit]\n\tgpgSign = true\n[gpg]\n\tprogram = false\n"
      ENV.delete("GIT_CONFIG_GLOBAL")
      ENV["XDG_CONFIG_HOME"] = test_root.to_s
      ENV["GIT_CONFIG_SYSTEM"] = config.to_s
      ENV["GIT_CONFIG_NOSYSTEM"] = "0"
      index = test_root/"caller.index"
      ENV["GIT_INDEX_FILE"] = index.to_s
      (origin/"notes").write "fixture"
      git "-C", origin, "add", "-f", "notes"
      git "-C", origin, "commit", "-qm", "fixture"

      expect([index.exist?, ENV.fetch("GIT_INDEX_FILE")]).to eq([false, index.to_s])
    end

    test_each([".config/git/ignore", "personal ignores"].product([false, true])) do |(path, replace)|
      it "honours the install user's #{path} with repository replacement #{replace}" do
        ignore = test_root/path
        ignore.dirname.mkpath
        ignore.write "personal.local\n"
        if path == "personal ignores"
          git "config", "--file", test_root/".gitconfig", "core.excludesFile", "~/#{path}"
        end
        (prefix/".homebrew-pkg-previous.git/index.lock").write "" if replace
        (prefix/"Library").mkpath
        FileUtils.touch [prefix/"Library/personal.local", prefix/"Library/scratch.local"]

        _, stderr, status = result
        expect([status.exitstatus, prefix.glob("Library/*.local"), prefix.glob(".homebrew-pkg-backup.*").any?])
          .to eq([0, [prefix/"Library/personal.local"], replace]), stderr
        expect(git("-C", prefix, "config", "--local", "--name-only", "--list").lines(chomp: true))
          .not_to include("core.excludesfile")
      end
    end

    it "reports an inaccessible configured excludes path and skips cleanup" do
      private_dir = test_root/"private"
      private_dir.mkpath
      ignore = private_dir/"ignore"
      ignore.write "personal.local\n"
      previous_git "config", "core.excludesFile", ignore
      private_dir.chmod(0000)
      (prefix/".homebrew-pkg-previous.git/index.lock").write ""
      (prefix/"Library").mkpath
      (prefix/"Library/personal.local").write "keep"

      _, stderr, status = result
      expect([status.exitstatus, stderr.include?(ignore.to_s), (prefix/"Library/personal.local").file?])
        .to eq([0, true, true]), stderr
    ensure
      private_dir&.chmod(0700)
    end

    it "finishes replacing Git and seeding the cache after an incomplete clean" do
      private_dir = prefix/"Library/private"
      private_dir.mkpath
      (private_dir/"notes").write "keep"
      private_dir.chmod(0555)
      (prefix/".homebrew-pkg-previous.git/index.lock").write ""

      _, stderr, status = result
      expect([status.exitstatus, stderr.include?("Library/private"), (private_dir/"notes").file?,
              (prefix/".git/index.lock").exist?, prefix.glob(".homebrew-pkg-backup.*/.git/index.lock").size,
              (test_root/"Library/Caches/Homebrew/api/formula.json").file?])
        .to eq([0, true, true, false, 1, true]), stderr
    ensure
      private_dir&.chmod(0755)
    end

    it "publishes a consistent release checkout after a concurrent branch switch" do
      previous_git "checkout", "--force", "local-work"
      (prefix/".gitignore").append_lines "# local-work"
      previous_git "commit", "-qam", "local ignore"
      previous_git "checkout", "--force", "stable"
      (prefix/".gitignore").append_lines "# before upgrade"
      FileUtils.cp(prefix/".gitignore", test_root/"before-upgrade")
      (test_root/"Developer Tools/usr/bin/git").write <<~SH
        #!/bin/bash
        set -e
        if [[ " $* " == *" -C . "* && ( " $* " == *" read-tree "* || " $* " == *" checkout "* ) ]]; then
          cmp "#{prefix}/.gitignore" "#{test_root}/before-upgrade"
          "#{Utils::Git.path}" -C "#{prefix}" checkout --force local-work
          echo switched >> "#{commands}"
        fi
        exec "#{Utils::Git.path}" "$@"
      SH

      _, stderr, status = result
      expect(commands.read.lines(chomp: true)).to include("switched")
      expect([status.exitstatus, git("-C", prefix, "branch", "--show-current"),
              git("-C", prefix, "rev-parse", "HEAD"), git("-C", prefix, "status", "--porcelain"),
              (prefix/".gitignore").read])
        .to eq([0, "stable", git("-C", origin, "rev-parse", "1.0.1"), "", (origin/".gitignore").read]), stderr
    end

    it "preserves the original branch when stable points to another branch" do
      previous_git "symbolic-ref", "refs/heads/stable", "refs/heads/local-work"
      original = previous_git "rev-parse", "local-work"

      _, stderr, status = result
      backup = prefix.glob(".homebrew-pkg-backup.*/.git").fetch(0)
      expect([status.exitstatus, git("--git-dir", backup, "rev-parse", "local-work"),
              git("-C", prefix, "describe", "--tags", "--exact-match")]).to eq([0, original, "1.0.1"]), stderr
    end

    it "falls back to an untagged packaged commit when the release fetch stalls" do
      git "-C", payload, "commit", "--allow-empty", "-qm", "untagged package"
      packaged = git("-C", payload, "rev-parse", "HEAD")
      server = TCPServer.new("127.0.0.1", 0)
      git "-C", payload, "remote", "set-url", "origin", "http://127.0.0.1:#{server.local_address.ip_port}"
      # Release a stuck fetch even if Git stops enforcing its low-speed timeout.
      watchdog = Thread.new do
        sleep 15
        server.close
      end
      _, stderr, status = result
      expect(stderr).to match(/operation too slow/i)
      expect([status.exitstatus, git("-C", prefix, "rev-parse", "stable")]).to eq([0, packaged]), stderr
    ensure
      watchdog&.kill
      server&.close
    end

    it "backs up a local branch with a corrupt blob and installs a healthy repository" do
      previous_git "symbolic-ref", "HEAD", "refs/heads/local-work"
      (prefix/"notes").write "local notes"
      previous_git "add", "-f", prefix/"notes"
      previous_git "commit", "-qm", "local notes"
      blob = previous_git "rev-parse", "local-work:notes"
      object = prefix/".homebrew-pkg-previous.git/objects/#{blob[0, 2]}/#{blob[2..]}"
      object.chmod(0644)
      object.binwrite("corrupt")

      _, stderr, status = result
      expect([status.exitstatus, prefix.glob(".homebrew-pkg-backup.*/.git/objects/#{blob[0, 2]}/#{blob[2..]}").size,
              git("-C", prefix, "fsck", "--full", "--no-dangling")]).to eq([0, 1, ""]), stderr
    end

    it "preserves the original refs, HEAD and index when updating the index fails" do
      previous_git "symbolic-ref", "HEAD", "refs/heads/local-work"
      refs = previous_git "show-ref", "--head"
      previous = prefix/".homebrew-pkg-previous.git"
      index = (previous/"index").binread
      (previous/"index.lock").write ""
      # The local transfer starts after the installer has copied its recovery snapshot.
      (test_root/"Developer Tools/usr/bin/git").write <<~SH
        #!/bin/bash
        set -e
        if [[ " $* " == *" fetch-pack "* ]]; then
          commit=$(git -C "#{prefix}" -c user.name=test -c user.email=test@example.org \\
            commit-tree 'local-work^{tree}' -p local-work -m concurrent)
          git -C "#{prefix}" update-ref refs/heads/during-upgrade "$commit"
        fi
        exec "#{Utils::Git.path}" "$@"
      SH

      stdout, stderr, status = result
      backup = prefix.glob(".homebrew-pkg-backup.*/.git").fetch(0)
      live = backup.parent/"live.git"
      expect(stdout).to include(backup.to_s, live.to_s)
      expect(git("--git-dir", live, "log", "-1", "--format=%s", "during-upgrade")).to eq("concurrent")
      expect([status.exitstatus, git("--git-dir", backup, "show-ref", "--head"),
              git("--git-dir", backup, "symbolic-ref", "HEAD"), (backup/"index").binread,
              git("-C", prefix, "describe", "--tags", "--exact-match")])
        .to eq([0, refs, "refs/heads/local-work", index, "1.0.1"]), stderr
    end

    it "keeps damaged metadata for recovery and installs a working repository" do
      FileUtils.rm_f (prefix/".homebrew-pkg-previous.git/objects/pack").glob("*.pack")

      _, stderr, status = result
      expect([status.exitstatus, prefix.glob(".homebrew-pkg-backup.*/.git/refs/heads/local-work").size,
              git("-C", prefix, "describe", "--tags", "--exact-match"), git("-C", prefix, "fsck", "--no-dangling")])
        .to eq([0, 1, "1.0.1", ""]), stderr
    end

    it "reports permission failures in the prefix and cache and completes the upgrade", :needs_macos do
      cache = test_root/"Library/Caches/Homebrew"
      cache.mkpath
      files = [prefix/"locked-prefix-file", cache/"locked-cache-file"]
      FileUtils.touch files
      FileUtils.chmod(0666, files)
      Utils.safe_popen_read("/usr/bin/chflags", "uchg", *files)

      _, stderr, status = result
      expect(stderr).to include("locked-prefix-file", "locked-cache-file")
      expect([status.exitstatus, git("-C", prefix, "describe", "--tags", "--exact-match"),
              (cache/"api/formula.json").file?, payload.exist?]).to eq([0, "1.0.1", true, false]), stderr
    ensure
      Utils.safe_popen_read("/usr/bin/chflags", "nouchg", *files)
    end
  end

  it "rejects another account's installation before changing ownership" do
    allow(self).to receive(:prefix_uid).and_return(install_uid + 1)

    expect([result("preinstall").last.exitstatus, result.last.exitstatus, commands.read]).to eq([1, 1, ""])
  end

  it "rejects a populated root-owned prefix before changing ownership or moving Git" do
    allow(self).to receive(:prefix_uid).and_return(0)
    (prefix/".git").mkpath

    expect([result("preinstall").last.exitstatus, result.last.exitstatus, (prefix/".git").directory?, commands.read])
      .to eq([1, 1, true, ""])
  end

  it "accepts an empty root-owned prefix" do
    allow(self).to receive(:prefix_uid).and_return(0)
    (prefix/"bin").rmdir

    expect([result("preinstall").last.exitstatus, commands.read.lines.first]).to eq([0, "chown pkg-user:admin .\n"])
  end

  test_each(%w[bin Library/Homebrew]) do |directory|
    it "reports an unwritable #{directory} before moving Git out of the prefix" do
      (prefix/".git").mkpath
      destination = prefix/directory
      destination.mkpath
      destination.chmod(0555)

      _, stderr, status = result("preinstall")
      expect([status.exitstatus, stderr.include?(destination.to_s),
              (prefix/".git").directory?]).to eq([1, true, true])
    end
  end

  it "requires a protected prefix parent before changing ownership" do
    allow(self).to receive(:parent_mode).and_return("drwxrwxr-x")

    expect([result("preinstall").last.exitstatus, result.last.exitstatus, commands.read]).to eq([1, 1, ""])
  end

  it "runs Git as the install user after setting ownership" do
    ENV["PKG_TEST_INHERITED"] = "discard"
    _, stderr, status = result
    log = commands.read.lines(chomp: true)

    expect([status.exitstatus, stderr, log.map { |line| line.split.first }, log.first, log.last])
      .to eq([0, "", %w[chown sudo fetch], "chown pkg-user:admin .", "fetch https unset"])
  end

  context "when developer tools are not installed" do
    sig { returns(T::Boolean) }
    let(:developer_tools) { false }

    it "reinstalls identical Git metadata without creating a backup" do
      FileUtils.cp_r payload/".git", prefix/".git"
      _, stderr, status = result

      expect([status.exitstatus, stderr, (prefix/".git/HEAD").read, prefix.glob(".homebrew-pkg-backup.*")])
        .to eq([0, "", "ref: refs/heads/stable\n", []])
    end

    it "installs and seeds the API cache without invoking Git" do
      _, stderr, status = result

      expect([status.exitstatus, stderr, (test_root/"Library/Caches/Homebrew/api/formula.json").file?]).to eq([
        0, "", true
      ])
    end
  end

  context "when sudo is unavailable" do
    sig { returns(T::Boolean) }
    let(:sudo_available) { false }

    it "runs Git and seeds the cache through login as the install user" do
      _, stderr, status = result

      expect([
        status.exitstatus, stderr,
        commands.read.lines(chomp: true).grep(/^login /),
        (test_root/"Library/Caches/Homebrew/api/formula.json").file?
      ]).to eq([0, "", ["login -f -l -q pkg-user"], true])
    end

    context "when Git fails" do
      sig { returns(Integer) }
      let(:git_exit_status) { 42 }

      it "fails before seeding the cache" do
        _, _, status = result

        expect([status.exitstatus, (test_root/"Library/Caches/Homebrew/api").exist?]).to eq([42, false])
      end
    end

    context "when developer tools are also unavailable" do
      sig { returns(T::Boolean) }
      let(:developer_tools) { false }

      it "installs and seeds the API cache" do
        _, stderr, status = result

        expect([status.exitstatus, stderr, (test_root/"Library/Caches/Homebrew/api/formula.json").file?]).to eq([
          0, "", true
        ])
      end
    end

    context "when the caller is not root" do
      sig { returns(Integer) }
      let(:caller_uid) { 502 }

      it "rejects account switching" do
        _, stderr, status = result

        expect([status.exitstatus, stderr, commands.read]).to eq([
          1, "Switching to the Homebrew installation user without sudo requires root.\n", ""
        ])
      end
    end
  end

  context "when xcode-select points to the root directory" do
    sig { returns(String) }
    let(:developer_dir) { "/" }

    it "does not invoke the system Git stub" do
      result

      expect(commands.read).not_to include("/usr/bin/git")
    end
  end

  context "when the install user has UID 0" do
    sig { returns(Integer) }
    let(:install_uid) { 0 }

    it "rejects the account before changing ownership or running Git" do
      _, stderr, status = result

      expect([status.exitstatus, stderr.lines.last, commands.read]).to eq([
        1, "A non-root Homebrew installation user is required.\n", ""
      ])
    end
  end

  context "when the install user is not an administrator" do
    sig { returns(String) }
    let(:install_groups) { "brew-users other-group" }

    # Keep each Sorbet signature with its let declaration.
    # rubocop:disable RSpec/ScatteredLet
    sig { returns(String) }
    let(:primary_group) { "brew-users" }
    # rubocop:enable RSpec/ScatteredLet

    it "uses the install user's custom primary group" do
      result

      expect([commands.read.lines.first, (prefix/"bin").stat.mode & 0777])
        .to eq(["chown pkg-user:brew-users .\n", 0775])
    end
  end

  context "when the install user's primary group is staff" do
    sig { returns(String) }
    let(:install_groups) { "staff" }

    it "removes group and other write permissions on installation and reinstallation" do
      cache = test_root/"Library/Caches/Homebrew"
      (prefix/"bin/brew").write "brew"

      2.times do
        stage_payload
        cache.mkpath
        (cache/"existing").write "cached"
        FileUtils.chmod_R(0777, prefix)
        FileUtils.chmod_R(0777, cache)
        _, stderr, status = result

        expect([status.exitstatus, stderr,
                [prefix, cache].flat_map { |root| root.find.to_a }.any? { |path| path.stat.mode.anybits?(0022) }])
          .to eq([0, "", false])
      end
    end

    test_each([
      [true, "077", "000"],
      [true, "000", "077"],
      [false, "077", "000"],
      [false, "000", "077"],
    ]) do |(sudo, parent_mask, child_mask)|
      it "preserves stricter umasks with #{[sudo, parent_mask, child_mask]}" do
        allow(self).to receive_messages(sudo_available: sudo, initial_umask: parent_mask, child_umask: child_mask)

        _, stderr, status = result

        expect([status.exitstatus, stderr, (test_root/"Library/Caches/Homebrew").stat.mode & 0777])
          .to eq([0, "", 0700])
      end
    end

    context "when the user is also an administrator" do
      sig { returns(String) }
      let(:install_groups) { "staff admin" }

      it "retains group write access and removes world write access on reinstall" do
        prefix.chmod(0777)
        (prefix/"bin").chmod(0777)
        (test_root/"Library/Caches/Homebrew").mkpath
        (test_root/"Library/Caches/Homebrew").chmod(0777)
        result

        expect([(prefix/"bin").stat.mode & 0777, (test_root/"Library/Caches/Homebrew").stat.mode & 0777])
          .to eq([0775, 0775])
      end
    end
  end
end
