# typed: true
# frozen_string_literal: true

require "sandbox"
require "extend/os/linux/sandbox" if OS.linux?

RSpec.describe Sandbox, :needs_linux do
  subject(:sandbox) { described_class.new }

  describe "::bubblewrap_executable" do
    let(:sandbox_class) do
      Class.new(Sandbox) do
        class << self
          attr_accessor :test_executable_candidate_paths

          def executable_candidate_paths = test_executable_candidate_paths
        end
      end
    end
    let(:setuid_dir) { mktmpdir }
    let(:usable_dir) { mktmpdir }
    let(:setuid_bubblewrap) { setuid_dir/"bwrap" }
    let(:usable_bubblewrap) { usable_dir/"bwrap" }

    before do
      FileUtils.touch setuid_bubblewrap
      FileUtils.chmod "+x", setuid_bubblewrap
      FileUtils.touch usable_bubblewrap
      FileUtils.chmod "+x", usable_bubblewrap
      sandbox_class.test_executable_candidate_paths = PATH.new(setuid_dir, usable_dir)
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with(setuid_bubblewrap).and_return(instance_double(File::Stat, setuid?: true))
    end

    it "searches Homebrew Bubblewrap before system Bubblewrap and skips setuid candidates" do
      expect(described_class.executable_candidate_paths.to_a).to start_with("#{HOMEBREW_PREFIX}/bin", "/usr/bin",
                                                                            "/bin")
      expect(sandbox_class.bubblewrap_executable).to eq(usable_bubblewrap)
    end

    it "raises when no suitable bubblewrap candidate exists" do
      sandbox_class.test_executable_candidate_paths = PATH.new(mktmpdir)

      expect { sandbox_class.bubblewrap_executable! }
        .to raise_error(RuntimeError, "Bubblewrap is required to use the Linux sandbox.")
    end
  end

  describe "::available?" do
    let(:sandbox_class) do
      Class.new(Sandbox) do
        class << self
          attr_accessor :test_executable_candidate_paths

          def executable_candidate_paths = test_executable_candidate_paths
        end
      end
    end
    let(:bubblewrap_dir) { mktmpdir }
    let(:bubblewrap) { bubblewrap_dir/"bwrap" }
    let(:fallback_bubblewrap_dir) { mktmpdir }
    let(:fallback_bubblewrap) { fallback_bubblewrap_dir/"bwrap" }
    let(:successful_result) { instance_double(SystemCommand::Result, success?: true) }
    let(:failed_result) { instance_double(SystemCommand::Result, success?: false, merged_output: "") }
    let(:bubblewrap_probe_args) do
      [
        "--unshare-user",
        "--unshare-ipc",
        "--unshare-pid",
        "--unshare-uts",
        "--unshare-cgroup-try",
        "--ro-bind", "/", "/",
        "--proc", "/proc",
        "--dev", "/dev",
        "true"
      ]
    end
    let(:bubblewrap_test_args) do
      [
        bubblewrap.to_s,
        *bubblewrap_probe_args,
        { err: :out },
      ]
    end

    before do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(true)
      FileUtils.touch bubblewrap
      FileUtils.chmod "+x", bubblewrap
      sandbox_class.test_executable_candidate_paths = PATH.new(bubblewrap_dir)
    end

    it "returns false when Linux sandboxing is disabled" do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(false)

      expect(sandbox_class.available?).to be(false)
    end

    it "returns false when bubblewrap is unavailable" do
      sandbox_class.test_executable_candidate_paths = PATH.new(mktmpdir)

      expect(sandbox_class.available?).to be(false)
      expect(sandbox_class.state).to eq(:missing)
    end

    it "probes unprivileged namespace support once" do
      expect(sandbox_class).to receive(:system_command).once.with(
        bubblewrap,
        args:         bubblewrap_probe_args,
        print_stderr: false,
      ).and_return(successful_result)

      expect(sandbox_class.available?).to be(true)
      expect(sandbox_class.state).to eq(:available)
      expect(sandbox_class.failure_reason).to be_nil
    end

    it "probes later usable Bubblewrap candidates if earlier candidates fail" do
      FileUtils.touch fallback_bubblewrap
      FileUtils.chmod "+x", fallback_bubblewrap
      sandbox_class.test_executable_candidate_paths = PATH.new(bubblewrap_dir, fallback_bubblewrap_dir)

      expect(sandbox_class).to receive(:system_command).with(
        bubblewrap,
        args:         bubblewrap_probe_args,
        print_stderr: false,
      ).and_return(failed_result)
      expect(sandbox_class).to receive(:system_command).with(
        fallback_bubblewrap,
        args:         bubblewrap_probe_args,
        print_stderr: false,
      ).and_return(successful_result)

      expect(sandbox_class.available?).to be(true)
    end

    it "reports setuid bubblewrap candidates" do
      allow(File).to receive(:stat).and_call_original
      allow(File).to receive(:stat).with(bubblewrap).and_return(instance_double(File::Stat, setuid?: true))

      expect(sandbox_class.available?).to be(false)
      expect(sandbox_class.state).to eq(:setuid)
      expect(sandbox_class.failure_reason).to include("setuid")
    end

    it "reports bubblewrap sandbox probe failures" do
      allow(sandbox_class).to receive(:system_command).and_return(failed_result)

      expect(sandbox_class.available?).to be(false)
      expect(sandbox_class.state).to eq(:unavailable)
      expect(sandbox_class.failure_reason).to include("cannot create a rootless sandbox")
    end

    it "prints bubblewrap sandbox probe failure output" do
      expect(sandbox_class).to receive(:system_command)
        .and_return(instance_double(SystemCommand::Result, success?:      false,
                                                           merged_output: "bwrap stdout\nbwrap stderr\n"))
      expect(sandbox_class).to receive(:opoo).with("bubblewrap test probe failed")

      expect { sandbox_class.available? }
        .to output("bwrap stdout\nbwrap stderr\n").to_stderr
    end

    it "does not treat generic bubblewrap sandbox probe failures as nested" do
      FileUtils.touch fallback_bubblewrap
      FileUtils.chmod "+x", fallback_bubblewrap
      sandbox_class.test_executable_candidate_paths = PATH.new(bubblewrap_dir, fallback_bubblewrap_dir)

      expect(Utils).to receive(:popen_read)
        .with(*bubblewrap_test_args)
        .and_return("bwrap: No permissions to create a new namespace\n")

      expect(sandbox_class.nested_sandbox?).to be(false)
    end

    it "treats a bubblewrap namespace nesting failure as nested" do
      expect(Utils).to receive(:popen_read)
        .with(*bubblewrap_test_args)
        .and_return("bwrap: Creating new namespace failed: " \
                    "nesting depth or /proc/sys/user/max_*_namespaces exceeded (ENOSPC)\n")

      expect(sandbox_class.nested_sandbox?).to be(true)
    end
  end

  describe "::configuration_commands" do
    let(:sandbox_class) { Class.new(described_class) }

    around do |example|
      with_env(GITHUB_ACTIONS: nil, HOMEBREW_GITHUB_HOSTED_RUNNER: nil) { example.run }
    end

    it "lists Linux sandbox sysctl commands" do
      expect(sandbox_class.configuration_commands).to eq([
        "sudo sysctl -w kernel.unprivileged_userns_clone=1",
        "sudo sysctl -w user.max_user_namespaces=28633",
        "sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true",
      ])
    end

    it "uses system Bubblewrap when configuring Linux sandbox sysctls" do
      allow(sandbox_class).to receive(:bubblewrap_executable).and_return(Pathname("/usr/bin/bwrap"))
      allow(Process).to receive(:euid).and_return(1000)
      expect(sandbox_class).not_to receive(:ensure_sandbox_installed!)
      expect(sandbox_class).to receive(:ohai).with("Configuring Bubblewrap...").ordered
      expect(sandbox_class).to receive(:system)
        .with("sudo", HOMEBREW_BREW_FILE.to_s, "setup-sandbox").and_return(true).ordered

      sandbox_class.configure!
    end

    it "does not configure Linux sandbox sysctls when Bubblewrap remains unavailable" do
      expect(sandbox_class).to receive(:bubblewrap_executable).twice.and_return(nil)
      expect(sandbox_class).to receive(:ensure_sandbox_installed!)
        .with(install_from_tests: true)
      expect(sandbox_class).not_to receive(:system)

      sandbox_class.configure!
    end

    it "installs Bubblewrap and configures Linux sandbox sysctls as root" do
      expect(sandbox_class).to receive(:bubblewrap_executable)
        .twice
        .and_return(nil, Pathname(HOMEBREW_PREFIX/"bin/bwrap"))
      allow(Process).to receive(:euid).and_return(0)
      expect(sandbox_class).to receive(:ensure_sandbox_installed!)
        .with(install_from_tests: true)
      expect(sandbox_class).to receive(:ohai).with("Configuring Bubblewrap...").ordered
      expect(sandbox_class).to receive(:system)
        .with(HOMEBREW_BREW_FILE.to_s, "setup-sandbox").and_return(true).ordered

      sandbox_class.configure!
    end

    it "raises when configuring Linux sandbox sysctls fails" do
      allow(sandbox_class).to receive(:bubblewrap_executable).and_return(Pathname("/usr/bin/bwrap"))
      allow(Process).to receive(:euid).and_return(0)
      allow(sandbox_class).to receive(:ohai)
      expect(sandbox_class).to receive(:system)
        .with(HOMEBREW_BREW_FILE.to_s, "setup-sandbox").and_return(false)

      expect { sandbox_class.configure! }.to raise_error(ErrorDuringExecution)
    end
  end

  describe "::sandbox_install_command" do
    let(:sandbox_class) { Class.new(described_class) }

    it "returns the distro-specific install command for the detected package manager" do
      allow(sandbox_class).to receive(:which).with("apt-get").and_return(nil)
      allow(sandbox_class).to receive(:which).with("dnf").and_return(Pathname("/usr/bin/dnf"))
      expect(sandbox_class.sandbox_install_command).to eq("sudo dnf install bubblewrap")
    end

    it "returns nil when no known package manager is found" do
      allow(sandbox_class).to receive(:which).and_return(nil)
      expect(sandbox_class.sandbox_install_command).to be_nil
    end
  end

  describe "::ensure_sandbox_installed!" do
    let(:sandbox_class) { Class.new(described_class) }

    around do |example|
      with_env(GITHUB_ACTIONS: nil, HOMEBREW_GITHUB_HOSTED_RUNNER: nil,
               HOMEBREW_INSTALLING_BUBBLEWRAP: nil, HOMEBREW_TESTS: nil) { example.run }
    end

    before do
      allow(Homebrew::EnvConfig).to receive(:sandbox_linux?).and_return(true)
    end

    it "does nothing when Homebrew Bubblewrap is already available" do
      expect(sandbox_class).to receive(:bubblewrap_executable)
        .once
        .and_return(Pathname(HOMEBREW_PREFIX/"bin/bwrap"))
      expect(Formula).not_to receive(:[])
      expect(sandbox_class).not_to receive(:which)
      expect(sandbox_class).not_to receive(:system)

      sandbox_class.ensure_sandbox_installed!
    end

    it "does nothing when system Bubblewrap is already available" do
      expect(sandbox_class).to receive(:bubblewrap_executable)
        .once
        .and_return(Pathname("/usr/bin/bwrap"))
      expect(Formula).not_to receive(:[])
      expect(sandbox_class).not_to receive(:which)
      expect(sandbox_class).not_to receive(:system)

      sandbox_class.ensure_sandbox_installed!
    end

    it "installs Bubblewrap with Homebrew before trying apt-get on GitHub Actions" do
      expect(sandbox_class).to receive(:bubblewrap_executable)
        .twice
        .and_return(nil, Pathname(HOMEBREW_PREFIX/"bin/bwrap"))
      expect(Formula).to receive(:[]).with("bubblewrap")
                                     .and_return(instance_double(Formula, ensure_installed!: nil))
      expect(sandbox_class).not_to receive(:which)
      expect(sandbox_class).not_to receive(:system)

      with_env(GITHUB_ACTIONS: "true", HOMEBREW_GITHUB_HOSTED_RUNNER: "1") do
        sandbox_class.ensure_sandbox_installed!
      end
    end

    it "falls back to sudo apt-get on GitHub Actions Ubuntu when Homebrew Bubblewrap is unavailable" do
      expect(sandbox_class).to receive(:bubblewrap_executable)
        .twice
        .and_return(nil)
      expect(Formula).to receive(:[]).with("bubblewrap")
                                     .and_return(instance_double(Formula, ensure_installed!: nil))
      expect(sandbox_class).to receive(:which).with("apt-get").and_return(Pathname("/usr/bin/apt-get"))
      expect(Process).to receive(:euid).and_return(1000)
      expect(sandbox_class).to receive(:ohai).with("Installing Bubblewrap...")
      expect(sandbox_class).to receive(:system)
        .with("sudo", "apt-get", "install", "--yes", "bubblewrap")
        .and_return(true)

      with_env(GITHUB_ACTIONS: "true", HOMEBREW_GITHUB_HOSTED_RUNNER: "1") do
        sandbox_class.ensure_sandbox_installed!
      end
    end

    it "falls back to apt-get as root on GitHub Actions Ubuntu when Homebrew Bubblewrap is unavailable" do
      expect(sandbox_class).to receive(:bubblewrap_executable)
        .twice
        .and_return(nil)
      expect(Formula).to receive(:[]).with("bubblewrap")
                                     .and_return(instance_double(Formula, ensure_installed!: nil))
      expect(sandbox_class).to receive(:which).with("apt-get").and_return(Pathname("/usr/bin/apt-get"))
      expect(Process).to receive(:euid).and_return(0)
      expect(sandbox_class).to receive(:ohai).with("Installing Bubblewrap...")
      expect(sandbox_class).to receive(:system)
        .with("apt-get", "install", "--yes", "bubblewrap")
        .and_return(true)

      with_env(GITHUB_ACTIONS: "true", HOMEBREW_GITHUB_HOSTED_RUNNER: "1") do
        sandbox_class.ensure_sandbox_installed!
      end
    end

    it "does not fall back to apt-get outside GitHub Actions Ubuntu" do
      expect(sandbox_class).to receive(:bubblewrap_executable)
        .twice
        .and_return(nil, nil)
      expect(Formula).to receive(:[]).with("bubblewrap")
                                     .and_return(instance_double(Formula, ensure_installed!: nil))
      expect(sandbox_class).not_to receive(:which)
      expect(sandbox_class).not_to receive(:system)

      with_env(GITHUB_ACTIONS: "true") do
        sandbox_class.ensure_sandbox_installed!
      end
    end

    it "does not fall back to apt-get outside GitHub Actions" do
      expect(sandbox_class).to receive(:bubblewrap_executable)
        .twice
        .and_return(nil, nil)
      expect(Formula).to receive(:[]).with("bubblewrap")
                                     .and_return(instance_double(Formula, ensure_installed!: nil))
      expect(sandbox_class).not_to receive(:which)
      expect(sandbox_class).not_to receive(:system)

      sandbox_class.ensure_sandbox_installed!
    end
  end

  describe "#bubblewrap_args" do
    let(:dir) { mktmpdir }
    let(:denied_dir) { mktmpdir }
    let(:tmpdir) { mktmpdir }
    let(:args) { sandbox.send(:bubblewrap_args, tmpdir.to_s) }

    it "maps allowed and denied writes to bind mounts" do
      sandbox.allow_write_path dir
      sandbox.deny_write_path denied_dir
      sandbox.deny_all_network

      expect(args).to include("--unshare-user", "--unshare-ipc", "--unshare-pid", "--unshare-net", "--new-session")
      expect(args.each_cons(3)).to include(["--bind", dir.to_s, dir.to_s])
      expect(args.each_cons(3)).to include(["--ro-bind", denied_dir.to_s, denied_dir.to_s])
    end

    it "runs from the sandbox tmpdir" do
      expect(args.each_cons(3)).to include(["--bind", tmpdir.to_s, tmpdir.to_s])
      expect(args.each_cons(2)).to include(["--chdir", tmpdir.to_s])
    end

    it "exposes the host filesystem read-only" do
      expect(args.each_cons(3)).to include(["--ro-bind", "/", "/"])
      expect(args.index("--ro-bind")).to be < args.index("--dev")
    end

    it "masks denied read directories" do
      sandbox.deny_read_path dir

      bind = args.each_cons(3).find { |arg| arg.fetch(0) == "--bind" && arg.fetch(2) == dir.to_s }
      expect(bind).not_to be_nil
      expect(Pathname(bind.fetch(1)).children).to be_empty
    end

    it "overlays Linux runtime filesystems" do
      expect(args.each_cons(2)).to include(["--dev", "/dev"], ["--proc", "/proc"])
    end

    it "does not need explicit mounts for allowed reads" do
      file = mktmpdir/"foo.rb"
      FileUtils.touch file
      sandbox.allow_read path: file

      expect(args.each_cons(3)).to include(["--ro-bind", "/", "/"])
      expect(args.each_cons(3)).not_to include(["--ro-bind", file.to_s, file.to_s])
    end

    it "uses Linux temp paths instead of macOS temp paths" do
      sandbox.allow_write_temp_and_cache

      expect(args).to include("/tmp", "/var/tmp", HOMEBREW_TEMP.to_s, HOMEBREW_CACHE.to_s)
      expect(args).not_to include("/private/tmp", "/private/var/tmp")
    end

    it "does not add Xcode write paths" do
      sandbox.allow_write_xcode

      expect(sandbox.send(:writable_paths)).to be_empty
    end

    it "rejects regex path filters" do
      sandbox.allow_write path: "^/tmp/homebrew-[^/]+$", type: :regex

      expect { args }.to raise_error(ArgumentError, /Linux sandbox does not support regex path filters/)
    end
  end

  describe "#run" do
    before do
      skip "Sandbox not implemented." if !ENV["CI"] && !described_class.available?
    end

    it "allows writing to an allowed path" do
      file = mktmpdir/"foo"
      sandbox.allow_write path: file
      sandbox.run "touch", file

      expect(file).to exist
    end

    it "fails when writing to a path that has not been allowed" do
      file = mktmpdir/"foo"

      expect do
        sandbox.run "touch", file
      end.to raise_error(ErrorDuringExecution)

      expect(file).not_to exist
    end

    it "returns the command exit status" do
      expect { sandbox.run "false" }.to raise_error(ErrorDuringExecution)
    end
  end
end
