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
        touch "Prepared/touched"
      end

      postflight_steps do
        mv "move-source", "Prepared/moved"
        ln_s "Prepared/moved", "PreparedLink", source_base: :relative, uninstall: true
      end

      uninstall_preflight_steps do
        mkdir "UninstallPrepared"
        touch "UninstallPrepared/touched"
      end

      uninstall_postflight_steps do
        move_children "UninstallPrepared", "UninstallMoved"
      end
    end
  end

  it "runs structured steps through installer artifact phases" do
    cask.staged_path.mkpath
    cask.config_path.dirname.mkpath
    (cask.staged_path/"move-source").write "moved"

    installer = Cask::Installer.new(cask, command: NeverSudoSystemCommand)
    installer.install_artifacts

    expect(cask.staged_path/"Prepared").to be_a_directory
    expect(cask.staged_path/"Prepared/touched").to exist
    expect(cask.staged_path/"Prepared/moved").to exist
    expect(cask.staged_path/"PreparedLink").to be_a_symlink

    installer.uninstall_artifacts

    expect(cask.staged_path/"PreparedLink").not_to exist
    expect(cask.staged_path/"UninstallMoved/touched").to exist
  end

  it "ignores a flight block when matching steps are defined" do
    cask = T.let(nil, T.nilable(Cask::Cask))
    expect do
      cask = Cask::Cask.new("with-install-steps-conflict") do
        version "1.2.3"
        sha256 :no_check
        url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"

        preflight do
          touch "ruby-block-ran"
        end

        preflight_steps do
          touch "steps-ran"
        end
      end
    end.to output(/`preflight` is ignored because `preflight_steps` is defined/).to_stderr

    cask = T.must(cask)
    cask.staged_path.mkpath
    cask.config_path.dirname.mkpath

    Cask::Installer.new(cask, command: NeverSudoSystemCommand).install_artifacts

    expect(cask.staged_path/"ruby-block-ran").not_to exist
    expect(cask.staged_path/"steps-ran").to exist
  end
end
