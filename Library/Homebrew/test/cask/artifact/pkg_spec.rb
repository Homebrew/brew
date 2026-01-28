# frozen_string_literal: true

RSpec.describe Cask::Artifact::Pkg, :cask do
  let(:cask) { Cask::CaskLoader.load(cask_path("with-installable")) }
  let(:fake_system_command) { class_double(SystemCommand) }

  before do
    InstallHelper.install_without_artifacts(cask)
  end

  describe "install_phase" do
    it "runs the system installer on the specified pkgs" do
      pkg = cask.artifacts.find { |a| a.is_a?(described_class) }

      expect(fake_system_command).to receive(:run!).with(
        "/usr/sbin/installer",
        args:         ["-pkg", cask.staged_path.join("MyFancyPkg", "Fancy.pkg"), "-target", "/"],
        sudo:         true,
        sudo_as_root: true,
        print_stdout: true,
        env:          {
          "LOGNAME"  => ENV.fetch("USER"),
          "USER"     => ENV.fetch("USER"),
          "USERNAME" => ENV.fetch("USER"),
        },
      )

      pkg.install_phase(command: fake_system_command)
    end
  end

  describe "choices" do
    let(:cask) { Cask::CaskLoader.load(cask_path("with-choices")) }

    it "passes the choice changes xml to the system installer" do
      pkg = cask.artifacts.find { |a| a.is_a?(described_class) }

      file = instance_double(Tempfile, path: Pathname.new("/tmp/choices.xml"))

      expect(file).to receive(:write).with <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
        \t<dict>
        \t\t<key>attributeSetting</key>
        \t\t<integer>1</integer>
        \t\t<key>choiceAttribute</key>
        \t\t<string>selected</string>
        \t\t<key>choiceIdentifier</key>
        \t\t<string>choice1</string>
        \t</dict>
        </array>
        </plist>
      XML

      expect(file).to receive(:close)
      expect(file).to receive(:unlink)
      expect(Tempfile).to receive(:open).and_yield(file)

      expect(fake_system_command).to receive(:run!).with(
        "/usr/sbin/installer",
        args:         [
          "-pkg", cask.staged_path.join("MyFancyPkg", "Fancy.pkg"),
          "-target", "/", "-applyChoiceChangesXML",
          cask.staged_path.join("/tmp/choices.xml")
        ],
        sudo:         true,
        sudo_as_root: true,
        print_stdout: true,
        env:          {
          "LOGNAME"  => ENV.fetch("USER"),
          "USER"     => ENV.fetch("USER"),
          "USERNAME" => ENV.fetch("USER"),
        },
      )

      pkg.install_phase(command: fake_system_command)
    end
  end
end
