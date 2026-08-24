# typed: false
# frozen_string_literal: true

RSpec.describe Cask::Artifact::AppImage, :cask do
  let(:cask) do
    Cask::Cask.new("example-appimage") do
      version "1.2.3"
      sha256 :no_check
      url "file:///example-1.2.3.AppImage"
      app_image "example-1.2.3.AppImage", target: "Example App.AppImage", binary: "example"
    end
  end
  let(:artifact) { cask.artifacts.find { |candidate| candidate.is_a?(described_class) } }
  let(:source) { cask.staged_path/"example-1.2.3.AppImage" }
  let(:target) { cask.config.appimagedir/"Example App.AppImage" }
  let(:binary) { cask.config.binarydir/"example" }
  let(:applications_dir) { Pathname(ENV.fetch("HOMEBREW_XDG_DATA_HOME"))/"applications" }
  let(:artifact_id) { Digest::SHA256.hexdigest("Example App.AppImage") }
  let(:desktop_file) { applications_dir/"homebrew-example-appimage-appimage-#{artifact_id}.desktop" }

  around do |example|
    test_xdg_data_home = mktmpdir/"xdg-data"
    ENV["HOMEBREW_XDG_DATA_HOME"] = test_xdg_data_home.to_s
    cask.staged_path.mkpath
    source.write <<~SH
      #!/bin/sh
      mkdir -p squashfs-root/usr/share/icons
      cat > squashfs-root/example.desktop <<'EOF'
      [Desktop Entry]
      Name=Example
      Exec=AppRun --open %U
      TryExec=/tmp/.mount_example/AppRun
      Icon=example
      EOF
      printf icon > squashfs-root/usr/share/icons/example.png
      ln -s usr/share/icons/example.png squashfs-root/.DirIcon
    SH
    source.chmod(0755)
    example.run
  ensure
    FileUtils.rm_rf cask.staged_path
    FileUtils.rm_rf target.dirname
    FileUtils.rm_f binary
    FileUtils.rm_rf test_xdg_data_home
  end

  it "installs the AppImage and its desktop menu metadata" do
    artifact.install_phase(command: NeverSudoSystemCommand, force: false)

    expect([target.readlink, binary.readlink, desktop_file.read,
            (desktop_file.realpath.dirname/"icon.png").read]).to eq([
              source,
              source,
              <<~DESKTOP,
                [Desktop Entry]
                Name=Example
                Exec=#{target} --open %U
                TryExec=#{target}
                Icon=#{desktop_file.realpath.dirname}/icon.png
              DESKTOP
              "icon",
            ])
  end

  it "removes only the desktop file installed by this artifact" do
    artifact.install_phase(command: NeverSudoSystemCommand, force: false)
    desktop_file.unlink
    desktop_file.write("unrelated")

    artifact.uninstall_phase(command: NeverSudoSystemCommand)

    expect([target.exist?, binary.exist?, desktop_file.read]).to eq([false, false, "unrelated"])
  end

  it "serializes the optional binary target" do
    expect(artifact.to_args).to eq([
      "example-1.2.3.AppImage",
      { target: "Example App.AppImage", binary: "example" },
    ])
  end

  it "does not link the optional binary when binaries are disabled" do
    artifact.install_phase(command: NeverSudoSystemCommand, force: false, binaries: false)

    expect([target.exist?, binary.exist?]).to eq([true, false])
  end

  it "does not replace an unrelated desktop file" do
    desktop_file.dirname.mkpath
    desktop_file.write("unrelated")

    artifact.install_phase(command: NeverSudoSystemCommand, force: false)

    expect(desktop_file.read).to eq("unrelated")
  end

  it "takes over a broken desktop link from an older cask version" do
    artifact.install_phase(command: NeverSudoSystemCommand, force: false)
    old_desktop_file = cask.caskroom_path/"0.9.0/.homebrew-appimage/#{artifact_id}/#{desktop_file.basename}"
    desktop_file.unlink
    desktop_file.make_symlink(old_desktop_file)

    artifact.install_phase(command: NeverSudoSystemCommand, force: false)

    expect(desktop_file.readlink).to eq(cask.staged_path/".homebrew-appimage/#{artifact_id}/#{desktop_file.basename}")
  end

  it "does not remove a desktop link installed by a newer cask version" do
    artifact.install_phase(command: NeverSudoSystemCommand, force: false)
    new_desktop_file = cask.caskroom_path/"2.0.0/.homebrew-appimage/#{artifact_id}/#{desktop_file.basename}"
    desktop_file.unlink
    desktop_file.make_symlink(new_desktop_file)

    artifact.uninstall_phase(command: NeverSudoSystemCommand)

    expect(desktop_file.readlink).to eq(new_desktop_file)
  end

  it "keeps desktop identities distinct for AppImages with different targets" do
    other_cask = Cask::Cask.new("example-appimage") do
      version "1.2.3"
      sha256 :no_check
      url "file:///other.AppImage"
      app_image "other.AppImage", target: "Other App.AppImage"
    end
    other_artifact = other_cask.artifacts.find { |candidate| candidate.is_a?(described_class) }
    other_source = other_cask.staged_path/"other.AppImage"
    other_source.dirname.mkpath
    FileUtils.cp source, other_source
    other_artifact.install_phase(command: NeverSudoSystemCommand, force: false)

    other_artifact_id = Digest::SHA256.hexdigest("Other App.AppImage")
    other_desktop_file = applications_dir/"homebrew-example-appimage-appimage-#{other_artifact_id}.desktop"

    expect([desktop_file.exist?, other_desktop_file.exist?]).to eq([false, true])
  end
end
