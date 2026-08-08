# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AbstractInstallSteps, :cask do
  before do
    allow(Sandbox).to receive(:available?).and_return(false)
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

    expect(run_step).not_to include("print_stdout", "suppress_stderr", "writable_paths")
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
    expect(sandbox).to receive(:run).once do |*args|
      expect(args).to include(HOMEBREW_LIBRARY_PATH/"cask_artifact.rb")

      payload = JSON.parse(Pathname(args.last).read)
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

  it "runs a flight block after matching steps during migration" do
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
