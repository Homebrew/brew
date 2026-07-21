# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AbstractInstallSteps, :cask do
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

    expect(run_step).not_to include("print_stdout", "suppress_stderr")
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
