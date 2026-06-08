# typed: true
# frozen_string_literal: true

require "cmd/config"
require "cmd/shared_examples/args_parse"

RSpec.describe Homebrew::Cmd::Config do
  let(:windows_cmd) do
    cmd = mktmpdir/"cmd.exe"
    cmd.write("")
    cmd.chmod(0755)
    cmd
  end

  it_behaves_like "parseable arguments"

  it "prints information about the current Homebrew configuration", :integration_test do
    expect { brew "config" }
      .to output(/HOMEBREW_VERSION: #{Regexp.escape HOMEBREW_VERSION}/o).to_stdout
      .and not_to_output.to_stderr
      .and be_a_success
  end

  it "prints HOMEBREW_CASK_OPTS_REQUIRE_SHA in env config output when set" do
    Homebrew.raise_deprecation_exceptions = false
    ENV["HOMEBREW_CASK_OPTS_REQUIRE_SHA"] = "1"
    output = StringIO.new

    SystemConfig.homebrew_env_config(output)

    expect(output.string).to include("HOMEBREW_CASK_OPTS_REQUIRE_SHA: 1")
  ensure
    Homebrew.raise_deprecation_exceptions = true
  end

  it "reads the Windows version on WSL", :needs_linux do
    allow(OS).to receive(:wsl?).and_return(true)
    stub_const("ORIGINAL_PATHS", [windows_cmd.dirname])
    allow(Utils).to receive(:popen_read)
      .with(windows_cmd, "/d", "/c", "reg", "query", "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion",
            err: :close)
      .and_return(<<~EOS)
        HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion
            ProductName    REG_SZ    Windows 10 Pro
            DisplayVersion    REG_SZ    25H2
            CurrentBuildNumber    REG_SZ    26200
            UBR    REG_DWORD    0x2109
      EOS

    expect(SystemConfig.windows_version).to eq("Windows 11 Pro (25H2) [26200.8457]")
  end

  it "prints the Windows version in config output on WSL", :needs_linux do
    output = StringIO.new

    allow(OS).to receive(:wsl?).and_return(true)
    allow(OS::Linux).to receive_messages(os_version: "Ubuntu 24.04.3 LTS", wsl_version: Version.new("2"))
    allow(SystemConfig).to receive_messages(
      homebrew_config:      nil,
      core_tap_config:      nil,
      homebrew_env_config:  nil,
      hardware:             nil,
      host_software_config: nil,
      windows_version:      "Windows 11 Pro (25H2) [26200.8457]",
    )

    SystemConfig.dump_verbose_config(output)

    expect(output.string).to include("Windows: Windows 11 Pro (25H2) [26200.8457]\n")
  end

  it "does not print HOMEBREW_EVAL_ALL unless it is directly set" do
    output = StringIO.new

    with_env(HOMEBREW_REQUIRE_TAP_TRUST: "1", HOMEBREW_EVAL_ALL: nil) do
      SystemConfig.homebrew_env_config(output)
    end

    expect(output.string).not_to include("HOMEBREW_EVAL_ALL")
  end
end
