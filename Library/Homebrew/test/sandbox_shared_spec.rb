# typed: false
# frozen_string_literal: true

require "sandbox"

RSpec.describe Sandbox do
  subject(:sandbox) { described_class.new }

  describe "::run_command" do
    let(:command_sandbox) { instance_double(described_class) }
    let(:writable_path) { mktmpdir }

    before do
      allow(described_class).to receive_messages(
        ensure_sandbox_installed!: nil,
        available?:                true,
        new:                       command_sandbox,
      )
      allow(command_sandbox).to receive_messages(
        allow_write_temp_and_cache: nil,
        allow_write_path:           nil,
        deny_read_home:             nil,
        deny_all_network:           nil,
        run:                        nil,
      )
    end

    it "runs a command with the requested writable path" do
      expect(command_sandbox).to receive(:allow_write_temp_and_cache).ordered
      expect(command_sandbox).to receive(:allow_write_path).with(writable_path.realpath).ordered
      expect(command_sandbox).to receive(:deny_read_home).ordered
      expect(command_sandbox).not_to receive(:deny_all_network)
      expect(command_sandbox).to receive(:run).with(
        "/bin/sh",
        "-c",
        "cd \"$1\" && shift && exec \"$@\"",
        "brew-sandbox-exec",
        writable_path.realpath,
        "make",
        "test",
      ).ordered

      described_class.run_command("make", "test", writable_path:)
    end

    it "can deny network access" do
      expect(command_sandbox).to receive(:deny_all_network)

      described_class.run_command("make", writable_path:, deny_network: true)
    end

    it "does not run unsandboxed when sandboxing is unavailable" do
      allow(described_class).to receive_messages(available?: false, failure_reason: "sandbox unavailable")
      expect(command_sandbox).not_to receive(:run)

      expect { described_class.run_command("make", writable_path:) }
        .to raise_error(RuntimeError, "sandbox unavailable")
    end

    it "raises a usage error when the writable path does not exist" do
      missing_path = writable_path/"missing"
      expect(command_sandbox).not_to receive(:run)

      expect { described_class.run_command("make", writable_path: missing_path) }
        .to raise_error(UsageError, "Invalid usage: `#{missing_path}` is not a writable directory.")
    end

    it "raises a usage error when the writable path is not a directory" do
      file_path = writable_path/"file"
      FileUtils.touch file_path
      expect(command_sandbox).not_to receive(:run)

      expect { described_class.run_command("make", writable_path: file_path) }
        .to raise_error(UsageError, "Invalid usage: `#{file_path}` is not a writable directory.")
    end
  end

  describe "::failure_reason" do
    let(:sandbox_class) { Class.new(described_class) }

    it "returns nil if the sandbox is available" do
      allow(sandbox_class).to receive(:state).and_return(:available)

      expect(sandbox_class.failure_reason).to be_nil
    end

    it "returns a sandbox failure reason if the sandbox is unavailable" do
      allow(sandbox_class).to receive(:state).and_return(:unavailable)

      expect(sandbox_class.failure_reason).to match(/sandbox/i)
    end
  end

  describe "::executable" do
    let(:sandbox_class) do
      Class.new(Sandbox) do
        class << self
          attr_accessor :test_executable_name, :unsuitable_executables

          def executable_name = test_executable_name

          def executable_usable?(candidate)
            unsuitable_executables.exclude?(candidate)
          end
        end
      end
    end
    let(:first_dir) { mktmpdir }
    let(:second_dir) { mktmpdir }
    let(:homebrew_bin) { mktmpdir }
    let(:executable_name) { "sandbox-tool" }
    let(:first_executable) { first_dir/executable_name }
    let(:second_executable) { second_dir/executable_name }
    let(:homebrew_executable) { homebrew_bin/executable_name }

    before do
      sandbox_class.test_executable_name = executable_name
      sandbox_class.unsuitable_executables = []
      stub_const("HOMEBREW_ORIGINAL_BREW_FILE", homebrew_bin/"brew")
    end

    it "uses the first suitable executable candidate" do
      FileUtils.touch first_executable
      FileUtils.chmod "+x", first_executable
      FileUtils.touch second_executable
      FileUtils.chmod "+x", second_executable
      stub_const("ORIGINAL_PATHS", [first_dir])

      with_env(PATH: second_dir.to_s) do
        expect(sandbox_class.executable).to eq(first_executable)
      end
    end

    it "skips unsuitable executable candidates" do
      FileUtils.touch first_executable
      FileUtils.chmod "+x", first_executable
      FileUtils.touch second_executable
      FileUtils.chmod "+x", second_executable
      stub_const("ORIGINAL_PATHS", [first_dir])
      sandbox_class.unsuitable_executables = [first_executable]

      with_env(PATH: second_dir.to_s) do
        expect(sandbox_class.executable).to eq(second_executable)
      end
    end

    it "falls back to the original Homebrew bin directory" do
      FileUtils.touch homebrew_executable
      FileUtils.chmod "+x", homebrew_executable
      stub_const("ORIGINAL_PATHS", [])

      with_env(PATH: mktmpdir.to_s) do
        expect(sandbox_class.executable).to eq(homebrew_executable)
      end
    end

    it "checks absolute executable paths directly" do
      FileUtils.touch first_executable
      FileUtils.chmod "+x", first_executable
      sandbox_class.test_executable_name = first_executable.to_s
      stub_const("ORIGINAL_PATHS", [])

      with_env(PATH: mktmpdir.to_s) do
        expect(sandbox_class.executable).to eq(first_executable)
      end
    end

    it "raises when no executable candidate exists" do
      stub_const("ORIGINAL_PATHS", [])

      with_env(PATH: mktmpdir.to_s) do
        expect { sandbox_class.executable! }
          .to raise_error(RuntimeError, "#{executable_name} is required to use the sandbox.")
      end
    end
  end

  describe "#path_filter" do
    # The OS-specific renderer quotes paths safely, so no character is rejected.
    ["'", '"', "(", ")", "\\", " ", ";", "#", "\n"].each do |char|
      it "allows paths containing #{char.inspect}" do
        expect { sandbox.path_filter(mktmpdir/"foo#{char}bar", :subpath) }.not_to raise_error
      end
    end
  end

  describe "#allow_read_if_exists" do
    it "allows reads for existing paths" do
      file = mktmpdir/"foo.rb"
      FileUtils.touch file

      sandbox.allow_read_if_exists path: file

      rule = sandbox.send(:profile).rules.fetch(-1)
      expect(rule).to have_attributes(allow: true, operation: "file-read*")
      expect(rule.filter).to have_attributes(path: file.realpath.to_s, type: :literal)
    end

    it "skips missing paths" do
      sandbox.allow_read_if_exists path: mktmpdir/"missing.rb"

      expect(sandbox.send(:profile).rules).to be_empty
    end

    it "skips nil paths" do
      sandbox.allow_read_if_exists path: nil

      expect(sandbox.send(:profile).rules).to be_empty
    end
  end

  describe "#deny_read_path" do
    it "denies reads for a subpath" do
      dir = mktmpdir/"foo"
      dir.mkpath

      sandbox.deny_read_path dir

      rule = sandbox.send(:profile).rules.fetch(-1)
      expect(rule).to have_attributes(allow: false, operation: "file-read*")
      expect(rule.filter).to have_attributes(path: dir.realpath.to_s, type: :subpath)
    end
  end

  describe "#deny_read_home" do
    let(:home) { mktmpdir/"home" }
    let(:prefix) { mktmpdir/"prefix" }
    let(:repository) { mktmpdir/"repository" }
    let(:temp) { mktmpdir/"tmp" }
    let(:cache) { mktmpdir/"cache" }
    let(:logs) { mktmpdir/"logs" }

    before do
      [home, prefix, repository, temp, cache, logs].each(&:mkpath)
      allow(Dir).to receive(:home).with(ENV.fetch("USER")).and_return(home.to_s)
      stub_const("HOMEBREW_PREFIX", prefix)
      stub_const("HOMEBREW_REPOSITORY", repository)
      stub_const("HOMEBREW_TEMP", temp)
      stub_const("HOMEBREW_CACHE", cache)
      stub_const("HOMEBREW_LOGS", logs)
    end

    it "denies reads from the real home" do
      sandbox.deny_read_home

      rule = sandbox.send(:profile).rules.fetch(-1)
      expect(rule).to have_attributes(allow: false, operation: "file-read*")
      expect(rule.filter).to have_attributes(path: home.realpath.to_s, type: :subpath)
    end

    [
      [:HOMEBREW_PREFIX, "prefix"],
      [:HOMEBREW_REPOSITORY, "repository"],
      [:HOMEBREW_CACHE, "cache"],
      [:HOMEBREW_TEMP, "tmp"],
      [:HOMEBREW_LOGS, "Library/Logs/Homebrew"],
    ].each do |constant, directory|
      it "skips the deny when #{constant} is inside the real home" do
        stub_const(constant.to_s, home/directory)
        # The constant under test is chosen dynamically per example.
        # rubocop:disable Sorbet/ConstantsFromStrings
        Object.const_get(constant).mkpath
        # rubocop:enable Sorbet/ConstantsFromStrings

        sandbox.deny_read_home

        expect(sandbox.send(:profile).rules).to be_empty
      end
    end

    [
      ["GITHUB_WORKSPACE", "workspace"],
      ["RUNNER_WORKSPACE", "runner-workspace"],
      ["RUNNER_TEMP", "runner-temp"],
    ].each do |env, directory|
      it "skips the deny when #{env} is inside the real home" do
        (home/directory).mkpath

        with_env(env => (home/directory).to_s) do
          sandbox.deny_read_home
        end

        expect(sandbox.send(:profile).rules).to be_empty
      end
    end

    it "skips the deny when a runner path resolves inside the real home" do
      (home/"workspace").mkpath
      workspace_link = mktmpdir/"workspace"
      FileUtils.ln_s home/"workspace", workspace_link

      with_env(GITHUB_WORKSPACE: workspace_link.to_s) do
        sandbox.deny_read_home
      end

      expect(sandbox.send(:profile).rules).to be_empty
    end

    it "denies known sensitive home paths when Homebrew needs home access" do
      cache = home/"Library/Caches/Homebrew"
      stub_const("HOMEBREW_CACHE", cache)
      allowed_dirs = [
        cache,
        home/"Library/Preferences",
        home/".config",
        home/".config/homebrew",
        home/"src",
      ]
      sensitive_dirs = [
        home/".claude",
        home/".config/gcloud",
        home/".config/gh",
        home/".config/fish",
        home/".config/huggingface",
        home/".config/pip",
        home/".config/pypoetry",
        home/".config/rclone",
        home/".kiro",
        home/".pip",
        home/".ssh",
        home/"Documents",
      ]
      sensitive_files = [
        home/".bash_login",
        home/".bash_logout",
        home/".bash_profile",
        home/".bashrc",
        home/".bash_history",
        home/".cache/huggingface/token",
        home/".claude.json",
        home/".config/composer/auth.json",
        home/".config/containers/auth.json",
        home/".config/sops/age/keys.txt",
        home/".cargo/credentials.toml",
        home/".gem/credentials",
        home/".git-credentials",
        home/".mysql_history",
        home/".netrc",
        home/".npmrc",
        home/".profile",
        home/".psql_history",
        home/".pypirc",
        home/".python_history",
        home/".terraform.d/credentials.tfrc.json",
        home/".zlogin",
        home/".zlogout",
        home/".zprofile",
        home/".zshenv",
        home/".zshrc",
        home/".zsh_history",
      ]

      [*allowed_dirs, *sensitive_dirs].each(&:mkpath)
      sensitive_files.each do |path|
        path.dirname.mkpath
        FileUtils.touch path
      end

      sandbox.deny_read_home

      denied = sandbox.send(:profile).rules.map { |rule| rule.filter&.path }
      expect(denied).to include(*(sensitive_dirs + sensitive_files).map { |path| path.realpath.to_s })
      expect(denied).not_to include(*allowed_dirs.map { |path| path.realpath.to_s })
    end

    it "does not deny arbitrary home entries whose names contain parentheses or backslashes" do
      stub_const("HOMEBREW_LOGS", home/"Library/Logs/Homebrew")
      teams_log = home/"Library/Logs/Microsoft Teams Helper (Renderer)"
      backslash_dir = home/"I:\\"
      [home/"Library/Logs/Homebrew", teams_log, backslash_dir, home/".ssh"].each(&:mkpath)

      sandbox.deny_read_home

      denied = sandbox.send(:profile).rules.map { |rule| rule.filter&.path }
      expect(denied).to include((home/".ssh").realpath.to_s)
      expect(denied).not_to include(teams_log.realpath.to_s, backslash_dir.realpath.to_s)
    end

    it "keeps the trust store readable so sandboxed builds can re-check tap trust" do
      stub_const("HOMEBREW_CACHE", home/"Library/Caches/Homebrew")
      config_home = home/".homebrew"
      [home/"Library/Caches/Homebrew", config_home, home/".ssh"].each(&:mkpath)
      trust_file = config_home/"trust.json"
      FileUtils.touch trust_file

      with_env(HOMEBREW_USER_CONFIG_HOME: config_home.to_s) do
        sandbox.deny_read_home
      end

      denied = sandbox.send(:profile).rules.map { |rule| rule.filter&.path }
      expect(denied).to include((home/".ssh").realpath.to_s)
      expect(denied).not_to include(trust_file.realpath.to_s)
    end

    it "keeps the XDG trust store readable so sandboxed builds can re-check tap trust" do
      stub_const("HOMEBREW_CACHE", home/"Library/Caches/Homebrew")
      config_home = home/".config/homebrew"
      gh_config = home/".config/gh"
      [home/"Library/Caches/Homebrew", config_home, gh_config, home/".ssh"].each(&:mkpath)
      trust_file = config_home/"trust.json"
      FileUtils.touch trust_file

      with_env(HOMEBREW_USER_CONFIG_HOME: config_home.to_s) do
        sandbox.deny_read_home
      end

      denied = sandbox.send(:profile).rules.map { |rule| rule.filter&.path }
      expect(denied).to include(gh_config.realpath.to_s)
      expect(denied).to include((home/".ssh").realpath.to_s)
      expect(denied).not_to include((home/".config").realpath.to_s)
      expect(denied).not_to include(trust_file.realpath.to_s)
    end

    it "keeps the Xcode directories readable so builds can use them", :needs_macos do
      developer = home/"Library/Developer"
      swiftpm = home/"Library/Caches/org.swift.swiftpm"
      [developer, swiftpm, home/".ssh"].each(&:mkpath)

      sandbox.deny_read_home

      denied = sandbox.send(:profile).rules.map { |rule| rule.filter&.path }
      expect(denied).not_to include(developer.realpath.to_s, swiftpm.realpath.to_s)
      expect(denied).to include((home/".ssh").realpath.to_s)
    end
  end

  describe "#allow_write_path_if_exists" do
    it "allows writes for existing paths" do
      dir = mktmpdir/"foo"
      dir.mkpath

      sandbox.allow_write_path_if_exists dir

      rule = sandbox.send(:profile).rules.fetch(0)
      expect(rule).to have_attributes(allow: true, operation: "file-write*")
      expect(rule.filter).to have_attributes(path: dir.realpath.to_s, type: :subpath)
    end

    it "skips missing paths" do
      sandbox.allow_write_path_if_exists mktmpdir/"missing"

      expect(sandbox.send(:profile).rules).to be_empty
    end

    it "skips nil paths" do
      sandbox.allow_write_path_if_exists nil

      expect(sandbox.send(:profile).rules).to be_empty
    end
  end
end
