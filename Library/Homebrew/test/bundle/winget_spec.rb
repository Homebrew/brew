# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/shared_examples/inventory"
require "bundle/extensions/winget"
require "bundle/skipper"

RSpec.describe Homebrew::Bundle::Winget do
  describe "checked Windows bridge" do
    let(:powershell) { mktmpdir/"powershell.exe" }
    let(:export_file) { mktmpdir/"export.json" }
    let(:inventory_output) { '{"Sources":[{"Packages":[{"PackageIdentifier":"Example.App"}]}]}' }
    let(:inventory_records) { Array.new(Homebrew::Bundle::Winget::SOURCES.length, "Example.App") }

    def write_inventory(output: "", status: 0)
      powershell.write <<~SH
        #!/bin/sh
        printf '%s' #{output.shellescape} > "$EXAMPLE_WINGET_EXPORT"
        printf '%s\\n' 'native inventory diagnostic' >&2
        exit #{status}
      SH
      powershell.chmod 0755
    end

    before do
      described_class.reset!
      ENV["EXAMPLE_WINGET_EXPORT"] = export_file.to_s
      write_inventory(output: inventory_output)
      allow(described_class).to receive(:package_manager_executable).and_return(Pathname("C:/WinGet/winget.exe"))
      allow(described_class).to receive(:which).and_call_original
      allow(described_class).to receive(:which).with("powershell.exe", ORIGINAL_PATHS).and_return(powershell)
      allow(described_class).to receive(:inventory_windows_path).and_call_original
      allow(described_class).to receive(:inventory_windows_path).with(export_file.to_s).and_return("C:/export.json")
      allow(Tempfile).to receive(:create).with(["brew-bundle-winget", ".json"])
                                         .and_yield(instance_double(File, path: export_file.to_s))
    end

    after do
      described_class.reset!
    end

    it_behaves_like "a failed inventory dump"

    it "does not cache a failed bridge and retries without reset" do
      write_inventory(output: inventory_output, status: 1)
      expect { described_class.apps }.to raise_error(ErrorDuringExecution)
      write_inventory(output: inventory_output)
      expect(described_class.apps.map(&:id)).to eq(inventory_records)
    end

    test_each_hash({ "missing" => Errno::ENOENT, "malformed" => RuntimeError }) do |export, error|
      it "retries after a successful command produces a #{export} export" do
        if export == "missing"
          powershell.write "#!/bin/sh\nrm -f \"$EXAMPLE_WINGET_EXPORT\"\n"
        else
          write_inventory(output: "not json")
        end

        expect { described_class.apps }.to raise_error(error)
        write_inventory(output: inventory_output)
        expect(described_class.apps.map(&:id)).to eq(inventory_records)
      end
    end

    it "rejects an unavailable PowerShell executable" do
      powershell.unlink

      expect { described_class.apps }.to raise_error(RuntimeError, /requires Windows PowerShell 5.1/)
    end

    it "skips name listing for empty exports" do
      write_inventory(output: '{"Sources":[]}')
      expect(described_class).not_to receive(:listed_app_names)
      expect(described_class.apps).to eq([])
    end

    it "caches successful empty exports" do
      write_inventory(output: '{"Sources":[]}')
      described_class.apps
      write_inventory(status: 1)
      expect(described_class.apps).to eq([])
    end

    it "does not cache a partially completed pair of sources" do
      allow(described_class).to receive(:listed_app_names).and_return({})
      allow(described_class).to receive(:exported_apps).and_call_original
      allow(described_class).to receive(:exported_apps).with(anything, source: "msstore")
                                                       .and_raise("second source unavailable")
      expect { described_class.apps }.to raise_error(/second source unavailable/)
      allow(described_class).to receive(:exported_apps).with(anything, source: "msstore").and_return([])
      expect(described_class.apps.map(&:id)).to eq(["Example.App"])
    end

    it "uses checked PowerShell execution and preserves quoted literal arguments" do
      expect(SystemCommand).to receive(:run!).with(
        powershell,
        args:         ["-NoProfile", "-NonInteractive", "-Command",
                       a_string_including("'Example''s ‘‘café’’ ‚‚‛‛; $(value)'", "$LASTEXITCODE = $null")],
        print_stderr: false,
      ).and_return(instance_double(SystemCommand::Result, stdout: ""))
      described_class.listed_app_names(Pathname("C:/WinGet/winget.exe"), source: "Example's ‘café’ ‚‛; $(value)")
    end
  end

  describe "strict inventory path conversion" do
    test_each_hash({ "exit 2"               => /exited with 2/,
                     "printf relative/path" => /Invalid Windows path/ }) do |command, error|
      it "rejects unsuccessful or nonabsolute conversion: #{command}" do
        converter = mktmpdir/"wslpath"
        converter.write "#!/bin/sh\n#{command}\n"
        converter.chmod 0755
        allow(described_class).to receive(:which).with("wslpath", ORIGINAL_PATHS).and_return(converter)

        expect do
          described_class.exported_apps(Pathname("C:/WinGet/winget.exe"), source: "winget")
        end.to raise_error(error)
      end
    end

    it "rejects a missing converter for Linux paths" do
      allow(described_class).to receive(:which).with("wslpath", ORIGINAL_PATHS).and_return(nil)
      expect do
        described_class.exported_apps(Pathname("C:/WinGet/winget.exe"),
                                      source: "winget")
      end.to raise_error(/requires wslpath/)
    end

    it "rejects an empty converted path" do
      allow(described_class).to receive(:which).with("wslpath", ORIGINAL_PATHS).and_return(Pathname("wslpath"))
      allow(described_class).to receive(:command_output).and_return("")
      expect do
        described_class.exported_apps(Pathname("C:/WinGet/winget.exe"),
                                      source: "winget")
      end.to raise_error(/Invalid Windows path/)
    end
  end

  describe "export validation" do
    test_each(["not json", "[]", "{}", '{"Sources":[{}]}',
               '{"Sources":[{"Packages":[{"PackageIdentifier":1}]}]}']) do |output|
      it "rejects invalid export #{output}" do
        expect { described_class.parse_export(output, source: "winget") }
          .to raise_error(RuntimeError, /Invalid WinGet export/)
      end
    end
  end

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
        allow(described_class).to receive(:prepare_inventory_command)
          .with(winget, args: ["list", "--source", "winget", "--accept-source-agreements", "--disable-interactivity",
                               "--nowarn"])
          .and_return([Pathname("powershell.exe"), "list script"])
        allow(described_class).to receive(:run_inventory_script)
          .with(Pathname("powershell.exe"), "list script")
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
        allow(described_class).to receive_messages(installed_app_records: [], export_apps: [])
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

      expect { described_class.cleanup!(items) }.to output("Uninstalled 1 winget package\n").to_stdout
    end

    it "reports failed removals by app name and source without changing PATH" do
      Homebrew.failed = false
      ENV["PATH"] = "/usr/bin:/bin"
      items = described_class.cleanup_items([
        Homebrew::Bundle::Dsl::Entry.new(:winget, "Steam", id: "Valve.Steam"),
      ])
      allow(Homebrew::Bundle).to receive(:system)
        .with(Pathname("winget.exe"), "uninstall", "--id", "XPDC2RH70K22MN",
              "--exact", "--source", "msstore",
              "--accept-source-agreements", "--disable-interactivity", verbose: false) do
        expect(ENV.fetch("PATH")).to eq("/usr/bin:/bin")
        false
      end

      expect do
        described_class.cleanup!(items)
      end.to(
        change(Homebrew, :failed?).from(false).to(true)
          .and(output(a_string_including("Discord (XPDC2RH70K22MN, msstore)")).to_stderr)
          .and(output("Uninstalled 0 winget packages\n").to_stdout),
      )
    end
  end
end
