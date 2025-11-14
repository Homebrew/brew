# frozen_string_literal: true

RSpec.describe Cask::Artifact::Flatpak, :cask do
  let(:cask) { Cask::CaskLoader.load(cask_path("with-flatpak")) }
  let(:cask_custom_remote) { Cask::CaskLoader.load(cask_path("with-flatpak-custom-remote")) }
  let(:fake_system_command) { class_double(SystemCommand) }
  let(:flatpak_command) { Pathname.new("/usr/bin/flatpak") }

  describe ".from_args" do
    it "creates a Flatpak artifact with app_id" do
      flatpak = described_class.from_args(cask, "org.gnome.Calculator")

      expect(flatpak.app_id).to eq("org.gnome.Calculator")
    end

    it "accepts :remote option" do
      flatpak = described_class.from_args(cask, "com.example.App", remote: "fedora")

      expect(flatpak.app_id).to eq("com.example.App")
      expect(flatpak.stanza_options[:remote]).to eq("fedora")
    end

    it "rejects invalid options" do
      expect do
        described_class.from_args(cask, "org.gnome.Calculator", invalid: "option")
      end.to raise_error(ArgumentError, /invalid/)
    end
  end

  describe "#summarize" do
    it "returns the app_id" do
      flatpak = cask.artifacts.find { |a| a.is_a?(described_class) }

      expect(flatpak.summarize).to eq("org.gnome.Calculator")
    end
  end

  describe "#remote" do
    it "defaults to flathub" do
      flatpak = cask.artifacts.find { |a| a.is_a?(described_class) }

      expect(flatpak.send(:remote)).to eq("flathub")
    end

    it "uses custom remote when specified" do
      flatpak = cask_custom_remote.artifacts.find { |a| a.is_a?(described_class) }

      expect(flatpak.send(:remote)).to eq("fedora")
    end
  end

  context "when on Linux", :needs_linux do
    before do
      InstallHelper.install_without_artifacts(cask)
    end

    describe "#install_phase" do
      let(:flatpak) { cask.artifacts.find { |a| a.is_a?(described_class) } }

      before do
        allow(flatpak).to receive(:which).with("flatpak").and_return(flatpak_command)
        allow(flatpak).to receive(:system).and_return(true)
        allow(Utils).to receive(:safe_popen_read).and_return("")
      end

      it "installs flatpak app from default remote" do
        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "remote-list", "--system", "--columns=name")
          .and_return("flathub\n")

        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "list", "--app", "--columns=application,origin")
          .and_return("")

        expect(fake_system_command).to receive(:run!).with(
          flatpak_command,
          args:         ["install", "-y", "--system", "flathub", "org.gnome.Calculator"],
          print_stdout: false,
        )

        flatpak.install_phase(command: fake_system_command, verbose: false)
      end

      it "installs flatpak app from custom remote" do
        flatpak_custom = cask_custom_remote.artifacts.find { |a| a.is_a?(described_class) }
        InstallHelper.install_without_artifacts(cask_custom_remote)

        allow(flatpak_custom).to receive(:which).with("flatpak").and_return(flatpak_command)
        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "remote-list", "--system", "--columns=name")
          .and_return("fedora\n")

        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "list", "--app", "--columns=application,origin")
          .and_return("")

        expect(fake_system_command).to receive(:run!).with(
          flatpak_command,
          args:         ["install", "-y", "--system", "fedora", "com.example.TestApp"],
          print_stdout: false,
        )

        flatpak_custom.install_phase(command: fake_system_command, verbose: false)
      end

      it "skips installation if already installed" do
        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "list", "--app", "--columns=application,origin")
          .and_return("org.gnome.Calculator\tflathub\n")

        expect(fake_system_command).not_to receive(:run!)

        flatpak.install_phase(command: fake_system_command, verbose: false)
      end

      it "auto-adds flathub remote if missing" do
        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "remote-list", "--system", "--columns=name")
          .and_return("", "flathub\n")

        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "list", "--app", "--columns=application,origin")
          .and_return("")

        expect(flatpak).to receive(:system).with(
          flatpak_command.to_s,
          "remote-add",
          "--if-not-exists",
          "--system",
          "flathub",
          "https://flathub.org/repo/flathub.flatpakrepo",
        )

        expect(fake_system_command).to receive(:run!)

        flatpak.install_phase(command: fake_system_command, verbose: false)
      end

      it "raises error if custom remote is not configured" do
        flatpak_custom = cask_custom_remote.artifacts.find { |a| a.is_a?(described_class) }
        InstallHelper.install_without_artifacts(cask_custom_remote)

        allow(flatpak_custom).to receive(:which).with("flatpak").and_return(flatpak_command)
        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "remote-list", "--system", "--columns=name")
          .and_return("flathub\n")

        expect do
          flatpak_custom.install_phase(command: fake_system_command, verbose: false)
        end.to raise_error(Cask::CaskError, /remote 'fedora' is not configured/)
      end

      it "auto-installs flatpak if not present" do
        allow(flatpak).to receive(:which).with("flatpak").and_return(nil, flatpak_command)

        expect(flatpak).to receive(:system).with(
          HOMEBREW_BREW_FILE,
          "install",
          "--formula",
          "flatpak",
        )

        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "remote-list", "--system", "--columns=name")
          .and_return("flathub\n")

        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "list", "--app", "--columns=application,origin")
          .and_return("")

        expect(fake_system_command).to receive(:run!)

        flatpak.install_phase(command: fake_system_command, verbose: false)
      end
    end

    describe "#uninstall_phase" do
      let(:flatpak) { cask.artifacts.find { |a| a.is_a?(described_class) } }

      before do
        InstallHelper.install_without_artifacts(cask)
        allow(flatpak).to receive(:which).with("flatpak").and_return(flatpak_command)
      end

      it "uninstalls flatpak app if installed" do
        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "list", "--app", "--columns=application,origin")
          .and_return("org.gnome.Calculator\tflathub\n")

        expect(fake_system_command).to receive(:run!).with(
          flatpak_command,
          args:         ["uninstall", "-y", "--system", "org.gnome.Calculator"],
          print_stdout: false,
        )

        flatpak.uninstall_phase(command: fake_system_command, verbose: false)
      end

      it "skips uninstall if not installed" do
        allow(Utils).to receive(:safe_popen_read)
          .with(flatpak_command, "list", "--app", "--columns=application,origin")
          .and_return("")

        expect(fake_system_command).not_to receive(:run!)

        flatpak.uninstall_phase(command: fake_system_command, verbose: false)
      end
    end
  end

  context "when on macOS", :needs_macos do
    describe "#install_phase" do
      it "prints warning and skips installation" do
        flatpak = cask.artifacts.find { |a| a.is_a?(described_class) }

        expect do
          flatpak.install_phase(command: fake_system_command, verbose: false)
        end.to output(/Flatpak artifacts are only supported on Linux/).to_stdout_from_any_process

        expect(fake_system_command).not_to receive(:run!)
      end
    end

    describe "#uninstall_phase" do
      it "skips uninstall on macOS" do
        flatpak = cask.artifacts.find { |a| a.is_a?(described_class) }

        expect(fake_system_command).not_to receive(:run!)

        flatpak.uninstall_phase(command: fake_system_command, verbose: false)
      end
    end
  end
end
