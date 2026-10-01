# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/winget"
require "bundle/skipper"

RSpec.describe Homebrew::Bundle::Winget do
  describe "checking" do
    let(:entry) do
      Homebrew::Bundle::Dsl::Entry.new(:winget, "PowerToys", id: "XP89DCGQ3K6VLD", source: "msstore")
    end

    before do
      allow(OS).to receive(:wsl?).and_return(true)
      allow(Homebrew::Bundle::Skipper).to receive(:skip?).with(entry).and_return(false)
    end

    it "checks app installation by source and ID" do
      allow(described_class).to receive(:installed_app_records).and_return([["XP89DCGQ3K6VLD", "msstore"]])
      expect(described_class.check([entry])).to be_empty
    end

    it "returns app names in failure messages" do
      allow(described_class).to receive(:installed_app_records).and_return([])
      expect(described_class.check([entry])).to eql(["WinGet Package PowerToys needs to be installed."])
    end
  end

  describe "dumping" do
    subject(:dumper) { described_class }

    context "when winget is not available" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "returns an empty list and dumps an empty string" do
        expect(dumper.apps).to be_empty
        expect(dumper.dump).to eql("")
      end
    end

    context "when winget is available" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("winget.exe"))
        allow(described_class).to receive(:export_apps)
          .with(Pathname.new("winget.exe"), source: "winget")
          .and_return(
            [
              Homebrew::Bundle::Winget::App.new(
                id:     "Microsoft.EdgeWebView2Runtime",
                name:   "Microsoft Edge WebView2 Runtime",
                source: "winget",
              ),
              Homebrew::Bundle::Winget::App.new(
                id: "Microsoft.OneDrive", name: "Microsoft OneDrive", source: "winget",
              ),
              Homebrew::Bundle::Winget::App.new(id: "Microsoft.WSL", name: "Windows Subsystem for Linux",
                                                source: "winget"),
              Homebrew::Bundle::Winget::App.new(
                id: "Valve.Steam", name: "Steam", source: "winget",
              ),
            ],
          )
        allow(described_class).to receive(:export_apps)
          .with(Pathname.new("winget.exe"), source: "msstore")
          .and_return(
            [
              Homebrew::Bundle::Winget::App.new(
                id: "9NBLGGH4NNS1", name: "App Installer", source: "msstore",
              ),
              Homebrew::Bundle::Winget::App.new(
                id: "XP89DCGQ3K6VLD", name: "PowerToys", source: "msstore",
              ),
              Homebrew::Bundle::Winget::App.new(id: "Microsoft.UI.Xaml.2.8", name: "Microsoft.UI.Xaml.2.8",
                                                source: "msstore"),
              Homebrew::Bundle::Winget::App.new(
                id: "9N0DX20HK701", name: "Windows Terminal", source: "msstore",
              ),
            ],
          )
      end

      it "returns app details and dumps Brewfile entries" do
        expect(dumper.apps.map { |app| [app.id, app.name, app.source] }).to eql([
          ["Microsoft.EdgeWebView2Runtime", "Microsoft Edge WebView2 Runtime", "winget"],
          ["Microsoft.OneDrive", "Microsoft OneDrive", "winget"],
          ["Microsoft.WSL", "Windows Subsystem for Linux", "winget"],
          ["Valve.Steam", "Steam", "winget"],
          ["9NBLGGH4NNS1", "App Installer", "msstore"],
          ["XP89DCGQ3K6VLD", "PowerToys", "msstore"],
          ["Microsoft.UI.Xaml.2.8", "Microsoft.UI.Xaml.2.8", "msstore"],
          ["9N0DX20HK701", "Windows Terminal", "msstore"],
        ])

        expect(dumper.dump).to eql(<<~BREWFILE.strip)
          winget "Steam", id: "Valve.Steam"
          winget "PowerToys", id: "XP89DCGQ3K6VLD", source: "msstore"
          winget "Windows Terminal", id: "9N0DX20HK701", source: "msstore"
        BREWFILE
      end

      it "resolves exported IDs through their source before dumping" do
        winget = Pathname.new("winget.exe")
        allow(described_class).to receive(:export_apps).and_call_original
        allow(described_class).to receive(:exported_apps).with(winget, source: "winget").and_return([
          Homebrew::Bundle::Winget::App.new(id: "Valve.Steam", name: "Valve.Steam", source: "winget"),
          Homebrew::Bundle::Winget::App.new(id: "Unknown.Package", name: "Unknown.Package", source: "winget"),
        ])
        allow(Utils).to receive(:popen_read)
          .with(winget, "list", "--source", "winget", "--accept-source-agreements", "--disable-interactivity",
                "--nowarn", err: :close)
          .and_return(<<~EOS)
            Name                                       Id                                          Version
            -----------------------------------------------------------------------------------------------
            Steam                                      Valve.Steam                                 2.10.91.91
          EOS

        expect(described_class.export_apps(winget, source: "winget").map { |app| [app.id, app.name] })
          .to eql([["Valve.Steam", "Steam"], ["Unknown.Package", "Unknown.Package"]])
      end

      it "parses human-readable names from winget list output" do
        output = <<~EOS
          \r   - \r
          Name       Id                Version
          ------------------------------------
          Steam      Valve.Steam       2.10.91.91
          Discord    XPDC2RH70K22MN    1.0.9188
        EOS

        expect(described_class.parse_list_names(output)).to eql(
          "valve.steam"    => "Steam",
          "xpdc2rh70k22mn" => "Discord",
        )
      end

      it "parses indented winget list output" do
        output = "    Name       Id                Version\n    " \
                 "------------------------------------\n    " \
                 "Long Name  Example.App       1.0\n"

        expect(described_class.parse_list_names(output)).to eql(
          "example.app" => "Long Name",
        )
      end
    end

    context "when winget is not in PATH" do
      it "finds winget in the default Windows app location" do
        allow(OS).to receive(:wsl?).and_return(true)
        allow(described_class).to receive(:which).with("winget.exe", ORIGINAL_PATHS).and_return(nil)
        winget = Pathname.new("/mnt/c/Users/BrewTest/AppData/Local/Microsoft/WindowsApps/winget.exe")
        expect(winget).to receive(:executable?).and_return(true)
        allow(described_class).to receive(:windows_apps_executables).and_return([winget])

        expect(described_class.package_manager_executable)
          .to eq(Pathname.new("/mnt/c/Users/BrewTest/AppData/Local/Microsoft/WindowsApps/winget.exe"))
      end

      it "converts default Windows app paths to WSL paths" do
        allow(described_class).to receive(:windows_local_appdata).and_return(nil)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("LOCALAPPDATA", nil).and_return("C:\\Users\\BrewTest\\AppData\\Local")
        allow(ENV).to receive(:fetch).with("USERPROFILE", nil).and_return(nil)

        expect(described_class.windows_apps_executables)
          .to eq([Pathname.new("/mnt/c/Users/BrewTest/AppData/Local/Microsoft/WindowsApps/winget.exe")])
      end
    end
  end

  describe "installing" do
    before do
      described_class.reset!
      allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("winget.exe"))
    end

    context "when app is installed" do
      before do
        allow(described_class).to receive(:installed_app_records).and_return([["XP89DCGQ3K6VLD", "msstore"]])
      end

      it "skips" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("PowerToys", id:     "XP89DCGQ3K6VLD",
                                                        source: "msstore")).to be(false)
      end
    end

    context "when app is not installed" do
      before do
        allow(described_class).to receive(:installed_app_records).and_return([])
      end

      it "installs app using its source and ID" do
        expect(described_class).to receive(:run_install_command)
          .with(Pathname("winget.exe"),
                ["install", "--id", "XP89DCGQ3K6VLD", "--exact", "--source", "msstore",
                 "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"],
                verbose: false, elevated: false)
          .and_return([true, ""])

        expect(described_class.preinstall!("PowerToys", id: "XP89DCGQ3K6VLD", source: "msstore")).to be(true)
        expect(described_class.install!("PowerToys", id: "XP89DCGQ3K6VLD", source: "msstore")).to be(true)
      end

      it "keeps the package dump cache filtered and sorted after installation" do
        allow(described_class).to receive(:export_apps).with(Pathname("winget.exe"),
                                                             source: "winget").and_return([
                                                               Homebrew::Bundle::Winget::App.new(
                                                                 id: "Valve.Steam", name: "Steam", source: "winget",
                                                               ),
                                                             ])
        allow(described_class).to receive(:export_apps).with(Pathname("winget.exe"),
                                                             source: "msstore").and_return([])

        expect(described_class.packages.map(&:name)).to eql(["Steam"])

        expect(described_class).to receive(:run_install_command)
          .with(Pathname("winget.exe"),
                ["install", "--id", "7zip.7zip", "--exact", "--source", "winget",
                 "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"],
                verbose: false, elevated: false)
          .and_return([true, ""])
        expect(described_class.install!("7-Zip", id: "7zip.7zip")).to be(true)

        expect(described_class).to receive(:run_install_command)
          .with(Pathname("winget.exe"),
                ["install", "--id", "Microsoft.VCLibs.140.00.UWPDesktop", "--exact", "--source", "msstore",
                 "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"],
                verbose: false, elevated: false)
          .and_return([true, ""])
        expect(described_class.install!("Microsoft VCLibs", id:     "Microsoft.VCLibs.140.00.UWPDesktop",
                                                            source: "msstore"))
          .to be(true)

        expect(described_class.packages.map { |app| [app.name, app.id, app.source] }).to eql([
          ["7-Zip", "7zip.7zip", "winget"],
          ["Steam", "Valve.Steam", "winget"],
        ])
      end

      it "retries elevated when winget reports an elevation-like installer failure" do
        expect(described_class).to receive(:run_install_command)
          .with(Pathname("winget.exe"),
                ["install", "--id", "Philips.HueSync", "--exact", "--source", "winget",
                 "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"],
                verbose: false, elevated: false)
          .and_return([false, "Installer failed with exit code: 1603\n"])
        expect(described_class).to receive(:run_install_command)
          .with(Pathname("winget.exe"),
                ["install", "--id", "Philips.HueSync", "--exact", "--source", "winget",
                 "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"],
                verbose: false, elevated: true)
          .and_return([true, ""])

        expect do
          expect(described_class.install!("Hue Sync", id: "Philips.HueSync")).to be(true)
        end.to output("WinGet install for Hue Sync may require Windows UAC/elevation; retrying elevated.\n")
          .to_stdout
      end

      it "suggests an elevated Windows install when the elevated retry fails" do
        expect(described_class).to receive(:run_install_command)
          .with(Pathname("winget.exe"),
                ["install", "--id", "Philips.HueSync", "--exact", "--source", "winget",
                 "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"],
                verbose: false, elevated: false)
          .and_return([false, "Installer failed with exit code: 1603\n"])
        expect(described_class).to receive(:run_install_command)
          .with(Pathname("winget.exe"),
                ["install", "--id", "Philips.HueSync", "--exact", "--source", "winget",
                 "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"],
                verbose: false, elevated: true)
          .and_return([false, ""])

        expect do
          expect(described_class.install!("Hue Sync", id: "Philips.HueSync")).to be(false)
        end.to output(<<~EOS).to_stdout
          WinGet install for Hue Sync may require Windows UAC/elevation; retrying elevated.
          WinGet failed to install Hue Sync (Philips.HueSync) from winget.
          The installer may require Windows UAC/elevation.
          Try installing it from an elevated Windows Terminal:
            winget install --id Philips.HueSync --exact --source winget --disable-interactivity
        EOS
      end

      it "suggests manual installation for installers that need UI" do
        expect(described_class).to receive(:run_install_command)
          .with(Pathname("winget.exe"),
                ["install", "--id", "Philips.HueSync", "--exact", "--source", "winget",
                 "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"],
                verbose: false, elevated: false)
          .and_return([false, "Installer requires interactive user input\n"])

        expect do
          expect(described_class.install!("Hue Sync", id: "Philips.HueSync")).to be(false)
        end.to output(<<~EOS).to_stdout
          WinGet failed to install Hue Sync (Philips.HueSync) from winget.
          The installer appears to require installer UI or user input, which brew bundle does not automate.
          Install it manually from Windows:
            winget install --id Philips.HueSync --exact --source winget
        EOS
      end
    end

    context "when winget is not available" do
      before do
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "raises an error" do
        expect do
          described_class.preinstall!("PowerToys", id: "XP89DCGQ3K6VLD", source: "msstore")
        end.to raise_error(RuntimeError, /winget.exe is not installed/)
      end
    end
  end

  describe "cleanup" do
    before do
      described_class.reset!
      allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("winget.exe"))
      allow(described_class).to receive(:exported_apps).with(Pathname("winget.exe"), source: "winget").and_return([
        Homebrew::Bundle::Winget::App.new(
          id: "Valve.Steam", name: "Steam", source: "winget",
        ),
      ])
      allow(described_class).to receive(:exported_apps).with(Pathname("winget.exe"), source: "msstore").and_return([
        Homebrew::Bundle::Winget::App.new(
          id: "XPDC2RH70K22MN", name: "Discord", source: "msstore",
        ),
      ])
    end

    it "returns packages not in Brewfile entries by source and ID" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:winget, "Steam", id: "Valve.Steam", source: "winget")]
      items = described_class.cleanup_items(entries)

      expect(items.map do |item|
        described_class.cleanup_item_name(item)
      end).to eql(["Discord (XPDC2RH70K22MN, msstore)"])
    end

    it "uses the default source when computing kept packages" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:winget, "Valve.Steam", id: "Valve.Steam", source: "winget")]
      expect(described_class.cleanup_items(entries).map do |item|
        described_class.cleanup_item_name(item)
      end)
        .to eql(["Discord (XPDC2RH70K22MN, msstore)"])
    end

    it "does not resolve app names during cleanup discovery" do
      expect(described_class).not_to receive(:listed_app_names)
      described_class.cleanup_items([Homebrew::Bundle::Dsl::Entry.new(:winget, "Steam", id: "Valve.Steam")])
    end

    it "uninstalls packages by exact ID and source" do
      items = described_class.cleanup_items([Homebrew::Bundle::Dsl::Entry.new(:winget, "Steam",
                                                                              id: "Valve.Steam")])
      expect(Homebrew::Bundle).to receive(:system)
        .with(Pathname("winget.exe"), "uninstall", "--id", "XPDC2RH70K22MN", "--exact", "--source", "msstore",
              "--accept-source-agreements", "--disable-interactivity", verbose: false)
        .and_return(true)

      expect { described_class.cleanup!(items) }.to output(/Uninstalled 1 WinGet package/).to_stdout
    end
  end
end
