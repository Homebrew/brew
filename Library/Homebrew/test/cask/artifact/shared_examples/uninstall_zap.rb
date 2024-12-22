# frozen_string_literal: true

require "benchmark"

RSpec.shared_examples "#uninstall_phase or #zap_phase" do
  subject { artifact }

  let(:artifact_dsl_key) { described_class.dsl_key }
  let(:artifact) { cask.artifacts.find { |a| a.is_a?(described_class) } }
  let(:fake_system_command) { class_double(SystemCommand) }

  context "when using :launchctl" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-launchctl")) }
    let(:launchctl_list_cmd) { %w[/bin/launchctl list my.fancy.package.service] }
    let(:launchctl_remove_cmd) { %w[/bin/launchctl remove my.fancy.package.service] }
    let(:unknown_response) { "launchctl list returned unknown response\n" }
    let(:service_info) do
      <<~EOS
        {
                "LimitLoadToSessionType" = "Aqua";
                "Label" = "my.fancy.package.service";
                "TimeOut" = 30;
                "OnDemand" = true;
                "LastExitStatus" = 0;
                "ProgramArguments" = (
                        "argument";
                );
        };
      EOS
    end

    it "works when job is owned by user" do
      allow(fake_system_command).to receive(:run)
        .with(
          "/bin/launchctl",
          args:         ["list", "my.fancy.package.service"],
          print_stderr: false,
          sudo:         false,
          sudo_as_root: false,
        )
        .and_return(instance_double(SystemCommand::Result, stdout: service_info))
      allow(fake_system_command).to receive(:run)
        .with(
          "/bin/launchctl",
          args:         ["list", "my.fancy.package.service"],
          print_stderr: false,
          sudo:         true,
          sudo_as_root: true,
        )
        .and_return(instance_double(SystemCommand::Result, stdout: unknown_response))

      expect(fake_system_command).to receive(:run)
        .with("/bin/launchctl", args: ["remove", "my.fancy.package.service"],
        must_succeed: false, sudo: false, sudo_as_root: false)
        .and_return(instance_double(SystemCommand::Result, success?: true))

      subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
    end

    it "works when job is owned by system" do
      allow(fake_system_command).to receive(:run)
        .with(
          "/bin/launchctl",
          args:         ["list", "my.fancy.package.service"],
          print_stderr: false,
          sudo:         false,
          sudo_as_root: false,
        )
        .and_return(instance_double(SystemCommand::Result, stdout: unknown_response))
      allow(fake_system_command).to receive(:run)
        .with(
          "/bin/launchctl",
          args:         ["list", "my.fancy.package.service"],
          print_stderr: false,
          sudo:         true,
          sudo_as_root: true,
        )
        .and_return(instance_double(SystemCommand::Result, stdout: service_info))

      expect(fake_system_command).to receive(:run)
        .with("/bin/launchctl", args: ["remove", "my.fancy.package.service"],
        must_succeed: true, sudo: true, sudo_as_root: true)
        .and_return(instance_double(SystemCommand::Result, success?: true))

      subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
    end
  end

  context "when using :launchctl with regex wildcard" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-launchctl-wildcard")) }
    let(:launchctl_regex) { "my.fancy.package.service.*" }
    let(:unknown_response) { "launchctl list returned unknown response\n" }
    let(:service_info) do
      <<~EOS
        {
                "LimitLoadToSessionType" = "Aqua";
                "Label" = "my.fancy.package.service.12345";
                "TimeOut" = 30;
                "OnDemand" = true;
                "LastExitStatus" = 0;
                "ProgramArguments" = (
                        "argument";
                );
        };
      EOS
    end
    let(:launchctl_list) do
      <<~EOS
        PID     Status  Label
        1111    0       my.fancy.package.service.12345
        -       0       com.apple.SafariHistoryServiceAgent
        -       0       com.apple.progressd
        555     0       my.fancy.package.service.test
      EOS
    end

    it "searches installed launchctl items" do
      expect(subject).to receive(:find_launchctl_with_wildcard)
        .with(launchctl_regex)
        .and_return(["my.fancy.package.service.12345"])

      allow(fake_system_command).to receive(:run)
        .with(
          "/bin/launchctl",
          args:         ["list", "my.fancy.package.service.12345"],
          print_stderr: false,
          sudo:         false,
          sudo_as_root: false,
        )
        .and_return(instance_double(SystemCommand::Result, stdout: unknown_response))
      allow(fake_system_command).to receive(:run)
        .with(
          "/bin/launchctl",
          args:         ["list", "my.fancy.package.service.12345"],
          print_stderr: false,
          sudo:         true,
          sudo_as_root: true,
        )
        .and_return(instance_double(SystemCommand::Result, stdout: service_info))

      expect(fake_system_command).to receive(:run)
        .with("/bin/launchctl", args: ["remove", "my.fancy.package.service.12345"],
        must_succeed: true, sudo: true, sudo_as_root: true)
        .and_return(instance_double(SystemCommand::Result, success?: true))

      subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
    end

    it "returns the matching launchctl services" do
      expect(subject).to receive(:system_command!)
        .with("/bin/launchctl", args: ["list"])
        .and_return(instance_double(SystemCommand::Result, stdout: launchctl_list))

      expect(subject.send(:find_launchctl_with_wildcard,
                          "my.fancy.package.service.*")).to eq(["my.fancy.package.service.12345",
                                                                "my.fancy.package.service.test"])
    end
  end

  context "when using :pkgutil" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-pkgutil")) }

    let(:main_pkg_id) { "my.fancy.package.main" }
    let(:agent_pkg_id) { "my.fancy.package.agent" }

    it "is supported" do
      main_pkg = Cask::Pkg.new(main_pkg_id, fake_system_command)
      agent_pkg = Cask::Pkg.new(agent_pkg_id, fake_system_command)

      expect(Cask::Pkg).to receive(:all_matching).and_return(
        [
          main_pkg,
          agent_pkg,
        ],
      )

      expect(main_pkg).to receive(:uninstall)
      expect(agent_pkg).to receive(:uninstall)

      subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
    end
  end

  context "when using :kext" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-kext")) }
    let(:kext_id) { "my.fancy.package.kernelextension" }

    it "is supported" do
      allow(subject).to receive(:system_command!)
        .with("/usr/sbin/kextstat", args: ["-l", "-b", kext_id], sudo: true, sudo_as_root: true)
        .and_return(instance_double(SystemCommand::Result, stdout: "loaded"))

      expect(subject).to receive(:system_command!)
        .with("/sbin/kextunload", args: ["-b", kext_id], sudo: true, sudo_as_root: true)
        .and_return(instance_double(SystemCommand::Result))

      expect(subject).to receive(:system_command!)
        .with("/usr/sbin/kextfind", args: ["-b", kext_id], sudo: true, sudo_as_root: true)
        .and_return(instance_double(SystemCommand::Result, stdout: "/Library/Extensions/FancyPackage.kext\n"))

      expect(subject).to receive(:system_command!)
        .with("/bin/rm", args: ["-rf", "/Library/Extensions/FancyPackage.kext"], sudo: true, sudo_as_root: true)

      subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
    end
  end

  context "when using :quit" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-quit")) }
    let(:bundle_id) { "my.fancy.package.app" }

    it "is skipped when the user is not a GUI user" do
      allow(User.current).to receive(:gui?).and_return false
      allow(subject).to receive(:running?).with(bundle_id).and_return(true)

      expect do
        subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
      end.to output(/Not logged into a GUI; skipping quitting application ID 'my.fancy.package.app'\./).to_stderr
    end

    it "quits a running application" do
      allow(User.current).to receive(:gui?).and_return true

      expect(subject).to receive(:running?).with(bundle_id).ordered.and_return(true)
      expect(subject).to receive(:quit).with(bundle_id)
                                       .and_return(instance_double(SystemCommand::Result, success?: true))
      expect(subject).to receive(:running?).with(bundle_id).ordered.and_return(false)

      expect do
        subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
      end.to output(/Application 'my.fancy.package.app' quit successfully\./).to_stdout
    end

    it "does not attempt to quit when upgrading or reinstalling" do
      next if artifact_dsl_key == :zap

      allow(User.current).to receive(:gui?).and_return true

      expect(subject).not_to receive(:running?)
      expect(subject).not_to receive(:quit)

      subject.public_send(:"#{artifact_dsl_key}_phase", upgrade: true, command: fake_system_command)
      subject.public_send(:"#{artifact_dsl_key}_phase", reinstall: true, command: fake_system_command)
    end

    it "tries to quit the application for 10 seconds" do
      allow(User.current).to receive(:gui?).and_return true

      allow(subject).to receive(:running?).with(bundle_id).and_return(true)
      allow(subject).to receive(:quit).with(bundle_id)
                                      .and_return(instance_double(SystemCommand::Result, success?: false))

      time = Benchmark.measure do
        expect do
          subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
        end.to output(/Application 'my.fancy.package.app' did not quit\./).to_stderr
      end

      expect(time.real).to be_within(3).of(10)
    end
  end

  context "when using :signal" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-signal")) }
    let(:bundle_id) { "my.fancy.package.app" }
    let(:signals) { %w[TERM KILL] }
    let(:unix_pids) { [12_345, 67_890] }

    it "is supported" do
      allow(subject).to receive(:running_processes).with(bundle_id)
                                                   .and_return(unix_pids.map { |pid| [pid, 0, bundle_id] })

      signals.each do |signal|
        expect(Process).to receive(:kill).with(signal, *unix_pids).and_return(1)
      end

      subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
    end

    it "does not send signal when upgrading or reinstalling" do
      next if artifact_dsl_key == :zap

      allow(subject).to receive(:running_processes).with(bundle_id)
                                                   .and_return(unix_pids.map { |pid| [pid, 0, bundle_id] })

      signals.each do |_signal|
        expect(Process).not_to receive(:kill)
      end

      subject.public_send(:"#{artifact_dsl_key}_phase", upgrade: true, command: fake_system_command)
      subject.public_send(:"#{artifact_dsl_key}_phase", reinstall: true, command: fake_system_command)
    end
  end

  [:delete, :trash].each do |directive|
    next if directive == :trash && ENV["HOMEBREW_TESTS_COVERAGE"].nil?

    context "when using :#{directive}" do
      let(:dir) { TEST_TMPDIR }
      let(:absolute_path) { Pathname.new("#{dir}/absolute_path") }
      let(:path_with_tilde) { Pathname.new("#{dir}/path_with_tilde") }
      let(:glob_path) { Pathname.new("#{dir}/glob_path") }
      let(:glob_path_alt) { Pathname.new("#{dir}/glob_path_alt") }
      let(:paths) { [absolute_path, path_with_tilde, glob_path, glob_path_alt] }
      let(:fake_system_command) { NeverSudoSystemCommand }
      let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-#{directive}")) }

      around do |example|
        ENV["HOME"] = dir

        FileUtils.touch paths

        example.run
      ensure
        FileUtils.rm_f paths
      end

      before do
        allow_any_instance_of(Cask::Artifact::AbstractUninstall).to receive(:trash_paths)
          .and_wrap_original do |method, *args, **kwargs|
            method.call(*args, **kwargs).tap do |trashed, _|
              FileUtils.rm_r trashed
            end
          end
      end

      it "is supported" do
        expect(paths).to all(exist)

        subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)

        paths.each do |path|
          expect(path).not_to exist
        end
      end
    end
  end

  [:script, :early_script].each do |script_type|
    context "when using #{script_type.inspect}" do
      let(:fake_system_command) { NeverSudoSystemCommand }
      let(:token) { "with-#{artifact_dsl_key}-#{script_type}".tr("_", "-") }
      let(:cask) { Cask::CaskLoader.load(cask_path(token.to_s)) }
      let(:script_pathname) { cask.staged_path.join("MyFancyPkg", "FancyUninstaller.tool") }

      it "is supported" do
        allow(fake_system_command).to receive(:run).with(any_args).and_call_original

        expect(fake_system_command).to receive(:run)
          .with(
            cask.staged_path.join("MyFancyPkg", "FancyUninstaller.tool"),
            args:         ["--please"],
            must_succeed: true,
            print_stdout: true,
            sudo:         false,
          )

        InstallHelper.install_without_artifacts(cask)
        subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
      end
    end
  end

  context "when using :login_item" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-#{artifact_dsl_key}-login-item")) }

    it "is supported" do
      expect(subject).to receive(:system_command)
        .with(
          "osascript",
          args: ["-e", 'tell application "System Events" to delete every login item whose name is "Fancy"'],
        )
        .and_return(instance_double(SystemCommand::Result, success?: true))

      subject.public_send(:"#{artifact_dsl_key}_phase", command: fake_system_command)
    end
  end
end
