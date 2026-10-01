# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AbstractInstallSteps, :cask do
  before do
    allow(Sandbox).to receive_messages(available?: false, avoid_nested_sandboxing?: false)
  end

  let(:cask) do
    Cask::Cask.new("with-install-steps") do
      version "1.2.3"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

      preflight_steps do
        mkdir_p "Prepared"
        set_permissions "Prepared", "0755"
        touch "Prepared/touched"
      end

      postflight_steps do
        move "move-source", "Prepared/moved"
        symlink "Prepared/moved", "PreparedLink", source_base: :relative, remove_on_uninstall: true
        run "/usr/bin/true"
      end

      uninstall_preflight_steps do
        mkdir_p "UninstallPrepared"
        touch "UninstallPrepared/touched"
      end

      uninstall_postflight_steps do
        move_contents "UninstallPrepared", "UninstallMoved"
      end
    end
  end

  it "runs structured steps through installer artifact phases" do
    cask.staged_path.mkpath
    cask.config_path.dirname.mkpath
    (cask.staged_path/"move-source").write "moved"

    installer = Cask::Installer.new(cask, command: NeverSudoSystemCommand)
    previous_umask = File.umask(077)
    begin
      installer.install_artifacts
    ensure
      File.umask(previous_umask)
    end

    expect(cask.staged_path/"Prepared").to be_a_directory
    expect((cask.staged_path/"Prepared").stat.mode & 0777).to eq(0755)
    expect(cask.staged_path/"Prepared/touched").to exist
    expect(cask.staged_path/"Prepared/moved").to exist
    expect(cask.staged_path/"PreparedLink").to be_a_symlink

    installer.uninstall_artifacts

    expect(cask.staged_path/"PreparedLink").not_to exist
    expect(cask.staged_path/"UninstallMoved/touched").to exist
  end

  it "omits cask command output defaults" do
    artifact = cask.artifacts.find { |candidate| candidate.is_a?(Cask::Artifact::PostflightSteps) }
    run_step = artifact.steps.find { |step| step["type"] == "run" }

    expect(run_step).not_to include("print_stdout", "suppress_stderr", "writable_paths", "network_access")
  end

  it "sandboxes complete step blocks, including system commands" do
    original_home = mktmpdir
    ENV["HOME"] = original_home.to_s
    cask = Cask::Cask.new("with-sandboxed-install-steps") do
      version "1.2.3"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

      postflight_steps do
        touch "Library/Application Support/cask-home-state", base: :home
        run "helper", args: ["/"], base: :staged_path,
                      writable_paths: ["/Library/Example"]
        run "/usr/bin/true"
      end
    end
    sandbox = instance_double(Sandbox).as_null_object
    cask.staged_path.mkpath
    cask.config_path.dirname.mkpath
    (cask.staged_path/"helper").write <<~SH
      #!/bin/sh
      touch "#{cask.staged_path}/sandbox-ran"
    SH
    (cask.staged_path/"helper").chmod 0755

    allow(Sandbox).to receive_messages(available?: true, new: sandbox)
    allow(sandbox).to receive(:allow_write_path)
    expect(Sandbox).to receive(:with_preserved_brew_file).and_yield
    expect(sandbox).to receive(:add_install_hook_rules).with(network_access_allowed: false)
    expect(sandbox).to receive(:allow_write_path).with(cask.caskroom_path)
    expect(sandbox).to receive(:allow_write_path).with(Pathname("/Library/Example"))
    expect(sandbox).not_to receive(:allow_write_path).with(Pathname("/"))
    expect(sandbox).to receive(:allow_write_path).with(original_home/"Library/Application Support")
    expect(sandbox).to receive(:allow_read)
      .with(path: original_home/"Library/Application Support", type: :subpath)
    expect(sandbox).to receive(:run).once do |*args, **|
      expect(args).to include(HOMEBREW_LIBRARY_PATH/"cask_artifact.rb")

      payload = JSON.parse(File.binread(args.fetch(-2)))
      expect(payload.fetch("action")).to eq("install_steps")
      expect(payload.fetch("steps").filter_map do |step|
        step.dig("command", "path") if step["type"] == "run"
      end)
        .to eq(%w[helper /usr/bin/true])
      Utils.safe_fork { exec(*args.map(&:to_s)) }
    end

    Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts

    expect(cask.staged_path/"sandbox-ran").to exist
    expect(original_home/"Library/Application Support/cask-home-state").to exist
  end

  it "allows network access for runs that request it" do
    cask = Cask::Cask.new("with-networked-install-step") do
      version "1.2.3"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

      postflight_steps do
        run "/usr/bin/true", network_access: true
      end
    end
    sandbox = instance_double(Sandbox).as_null_object
    cask.staged_path.mkpath
    cask.config_path.dirname.mkpath

    allow(Sandbox).to receive_messages(available?: true, new: sandbox)
    allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
    expect(sandbox).to receive(:add_install_hook_rules).with(network_access_allowed: true)
    expect(sandbox).to receive(:run)

    Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts
  end

  context "when install steps may require sudo" do
    it "runs privileged steps from separate sandbox phases in the parent process" do
      cask = Cask::Cask.new("with-parent-privileged-install-steps") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        preflight_steps do
          run "/usr/bin/true", sudo: true
        end

        postflight_steps do
          run "/usr/bin/true", sudo: true
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      command = class_double(SystemCommand)
      parent_pid = Process.pid
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*args, passthrough_stdin:, child_message_handler:|
        expect(passthrough_stdin).to be(false)
        Utils.safe_fork(child_message_handler:) { exec(*args.map(&:to_s)) }
      end
      expect(command).to receive(:run).twice do |_, sudo:, **|
        expect(sudo).to be(true)
        expect(Process.pid).to eq(parent_pid)
      end

      Cask::Installer.new(cask, command:).install_artifacts
    end

    it "rejects requests for steps that are not privileged" do
      cask = Cask::Cask.new("with-invalid-parent-step-request") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          touch "unprivileged"
          run "/usr/bin/true", sudo: true
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*_, child_message_handler:, **|
        child_message_handler.call(
          JSON.generate(
            "type"  => Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_REQUEST,
            "index" => 0,
          ),
        )
      end

      expect do
        Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts
      end.to raise_error(ArgumentError, "Cask install step 0 is not privileged.")
    end

    it "rejects child messages that are not privileged step requests" do
      cask = Cask::Cask.new("with-non-request-child-messages") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          run "/usr/bin/true", sudo: true
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*_, child_message_handler:, **|
        messages = ["not JSON", "null", "5", "[1]", "true", "{}", '{"type":"other"}']
        messages.each do |message|
          expect { child_message_handler.call(message) }
            .to raise_error(ArgumentError, "Invalid privileged cask child message.")
        end
      end

      Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts
    end

    it "rejects invalid privileged step indices" do
      cask = Cask::Cask.new("with-invalid-parent-step-index") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          run "/usr/bin/true", sudo: true
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*_, child_message_handler:, **|
        child_message_handler.call(
          JSON.generate(
            "type"  => Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_REQUEST,
            "index" => "0",
          ),
        )
      end

      expect do
        Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts
      end.to raise_error(ArgumentError, 'Invalid privileged cask install step index: "0"')
    end

    it "rejects out-of-range privileged step indices" do
      cask = Cask::Cask.new("with-out-of-range-parent-step-index") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          run "/usr/bin/true", sudo: true
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*_, child_message_handler:, **|
        child_message_handler.call(
          JSON.generate(
            "type"  => Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_REQUEST,
            "index" => 99,
          ),
        )
      end

      expect do
        Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts
      end.to raise_error(IndexError)
    end

    it "rejects replayed privileged step requests" do
      cask = Cask::Cask.new("with-replayed-parent-step-request") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          run "/usr/bin/true", sudo: true
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      command = class_double(SystemCommand)
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*_, child_message_handler:, **|
        request = JSON.generate(
          "type"  => Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_REQUEST,
          "index" => 0,
        )
        expect(child_message_handler.call(request))
          .to eq(Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_SUCCEEDED)
        child_message_handler.call(request)
      end
      expect(command).to receive(:run).once

      expect do
        Cask::Installer.new(cask, command:).install_artifacts
      end.to raise_error(ArgumentError, "Privileged cask install steps must be requested in order.")
    end

    it "re-evaluates privileged step guards in the parent" do
      cask = Cask::Cask.new("with-guarded-parent-step-request") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          if_path_exists "missing" do
            run "/usr/bin/true", sudo: true
          end
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      command = class_double(SystemCommand)
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*_, child_message_handler:, **|
        response = child_message_handler.call(
          JSON.generate(
            "type"  => Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_REQUEST,
            "index" => 0,
          ),
        )
        expect(response).to eq(Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_SUCCEEDED)
      end
      expect(command).not_to receive(:run)

      Cask::Installer.new(cask, command:).install_artifacts
    end

    it "preserves parent guard snapshots across privileged step requests" do
      guard_path = mktmpdir/"guard"
      cask = Cask::Cask.new("with-shared-guard-parent-step-requests") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          unless_path_exists guard_path do
            run "/usr/bin/true", sudo: true
            run "/usr/bin/true", sudo: true
          end
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      command = class_double(SystemCommand)
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*_, child_message_handler:, **|
        2.times do |index|
          response = child_message_handler.call(
            JSON.generate(
              "type"  => Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_REQUEST,
              "index" => index,
            ),
          )
          expect(response).to eq(Homebrew::InstallSteps::Runner::PRIVILEGED_STEP_SUCCEEDED)
        end
      end
      expect(command).to receive(:run).twice do
        guard_path.mkpath
      end

      Cask::Installer.new(cask, command:).install_artifacts
    end

    it "fails clearly when a privileged step has no parent message channel" do
      cask = Cask::Cask.new("without-parent-message-channel") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          run "/usr/bin/true", sudo: true
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*args, **|
        Utils.safe_fork { exec(*args.map(&:to_s)) }
      end

      expect do
        Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts
      end.to raise_error(RuntimeError, /Privileged cask install step 0 requires a parent message channel/)
    end

    it "preserves errors raised by a parent-side privileged step" do
      cask = Cask::Cask.new("with-failing-parent-privileged-install-step") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        postflight_steps do
          run "/usr/bin/false", sudo: true
        end
      end
      sandbox = instance_double(Sandbox).as_null_object
      command = class_double(SystemCommand)
      cask.staged_path.mkpath
      cask.config_path.dirname.mkpath

      allow(Sandbox).to receive_messages(available?: true, new: sandbox)
      allow(sandbox).to receive(:allow_write_path)
      allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
      allow(sandbox).to receive(:run) do |*args, child_message_handler:, **|
        Utils.safe_fork(child_message_handler:) { exec(*args.map(&:to_s)) }
      end
      allow(command).to receive(:run).and_raise("parent privileged step failed")

      expect do
        Cask::Installer.new(cask, command:).install_artifacts
      end.to raise_error(RuntimeError, "parent privileged step failed")
    end

    {
      "an explicitly privileged command" => proc { run "/usr/bin/true", sudo: true },
      "a conditionally privileged step"  => proc { remove "/usr/local/example", sudo: :if_needed },
      "an ownership step"                => proc { set_ownership "/usr/local/example" },
      "a keychain certificate step"      => proc { delete_keychain_certificates "Example" },
    }.each do |description, step|
      it "routes #{description} to the parent process" do
        cask = Cask::Cask.new("with-sandboxed-sudo-install-steps") do
          version "1.2.3"
          sha256 :no_check
          url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

          postflight_steps(&step)
        end
        sandbox = instance_double(Sandbox).as_null_object
        cask.staged_path.mkpath
        cask.config_path.dirname.mkpath

        allow(Sandbox).to receive_messages(available?: true, new: sandbox)
        allow(sandbox).to receive(:allow_write_path)
        allow(Sandbox).to receive(:with_preserved_brew_file).and_yield
        expect(sandbox).not_to receive(:allow_process_exec)
        expect(sandbox).to receive(:run) do |*_, passthrough_stdin:, child_message_handler:|
          expect(passthrough_stdin).to be(false)
          expect(child_message_handler).to be_a(Proc)
        end

        Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts
      end
    end
  end

  it "runs a flight block after matching steps during migration" do
    ENV["HOMEBREW_DEVELOPER"] = nil
    Homebrew.raise_deprecation_exceptions = false
    cask = Cask::Cask.new("with-install-steps-bridge") do
      version "1.2.3"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

      preflight_steps do
        touch "steps-ran"
      end

      preflight do
        raise "preflight steps did not run first" unless (staged_path/"steps-ran").exist?

        FileUtils.touch staged_path/"ruby-block-ran"
      end
    end

    cask.staged_path.mkpath
    cask.config_path.dirname.mkpath

    Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts

    expect(cask.staged_path/"ruby-block-ran").to exist
    expect(cask.staged_path/"steps-ran").to exist
  end
end
