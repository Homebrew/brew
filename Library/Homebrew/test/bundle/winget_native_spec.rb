# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/extensions/winget"

RSpec.describe Homebrew::Bundle::Winget do
  let(:native_directory) { mktmpdir("winget") }
  let(:executable) { native_directory/"fixture.exe" }
  let(:powershell) do
    which("powershell.exe", ORIGINAL_PATHS) ||
      Pathname("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
  end
  let(:no_applications_status) { "8A150014" }

  def windows_path(path)
    Utils.safe_popen_read("wslpath", "-w", path.to_s).chomp
  end

  before do
    skip "Requires WSL and Windows PowerShell 5.1." unless OS.wsl?

    described_class.reset!
    SystemCommand.run!(powershell, args: ["-NoProfile", "-NonInteractive", "-Command", <<~POWERSHELL])
      $ErrorActionPreference = 'Stop'
      if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
        throw 'Windows PowerShell 5.1 required'
      }
      $source = Get-Content #{described_class.powershell_quote(windows_path(fixture("winget.cs")))} -Raw -Encoding UTF8
      $output = #{described_class.powershell_quote(windows_path(executable))}
      Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $output -OutputType ConsoleApplication
    POWERSHELL
    (native_directory/"exit-code.txt").write "00000000"
    allow(described_class).to receive(:package_manager_executable).and_return(executable)
  end

  after do
    described_class.reset!
  end

  it "reads all configured sources through native execution with Unicode names" do
    expect(described_class.apps.map { |app| [app.name, app.source] })
      .to eq(Homebrew::Bundle::Winget::SOURCES.map { |source| ["Example café", source] })
  end

  test_each_hash({ "80070000" => "zero low byte",
                   "DEAD0014" => "same low byte as no applications" }) do |status, reason|
    it "rejects native failure 0x#{status} (#{reason}) without truncating its status" do
      (native_directory/"exit-code.txt").write status

      expect { described_class.apps }
        .to raise_error(ErrorDuringExecution, /native diagnostic café.*0x#{status}/m)
    end
  end

  it "accepts the exact no-applications status for export" do
    (native_directory/"exit-code.txt").write no_applications_status

    expect(described_class.apps).to eq([])
  end

  it "rejects the no-applications status for list" do
    (native_directory/"exit-code.txt").write no_applications_status

    expect { described_class.listed_app_names(executable, source: "winget") }
      .to raise_error(ErrorDuringExecution, /0x#{no_applications_status}/)
  end

  it "propagates failure to write the canonical empty export" do
    (native_directory/"exit-code.txt").write no_applications_status
    allow(Tempfile).to receive(:create).with(["brew-bundle-winget", ".json"])
                                       .and_yield(instance_double(File,
                                                                  path: (native_directory/"absent/export.json").to_s))

    expect { described_class.exported_apps(executable, source: "winget") }.to raise_error(ErrorDuringExecution)
  end

  test_each(["'", "\u2018", "\u2019", "\u201A", "\u201B"]) do |quote|
    context "with U+#{quote.ord.to_s(16).upcase} in executable and export paths" do
      let(:quoted_directory) { native_directory/"Example#{quote}s café; $(Write-Output unexpected)" }
      let(:quoted_executable) { quoted_directory/"fixture.exe" }

      before do
        quoted_directory.mkpath
        FileUtils.cp(executable, quoted_executable)
        FileUtils.cp(native_directory/"exit-code.txt", quoted_directory/"exit-code.txt")
        allow(Tempfile).to receive(:create).and_wrap_original do |original, basename, &block|
          original.call(basename, quoted_directory, &block)
        end
      end

      it "preserves literal arguments through native export and list" do
        expect(described_class.export_apps(quoted_executable, source: "winget"))
          .to contain_exactly(have_attributes(id: "Example.App", name: "Example café"))
      end

      it "writes the canonical empty export as BOM-free UTF-8" do
        (quoted_directory/"exit-code.txt").write no_applications_status
        allow(Tempfile).to receive(:create).and_wrap_original do |original, basename, &block|
          original.call(basename, quoted_directory) do |file|
            apps = block.call(file)
            expect(File.binread(file.path)).to eq('{"Sources":[]}')
            apps
          end
        end

        expect(described_class.exported_apps(quoted_executable, source: "winget")).to eq([])
      end
    end
  end
end
