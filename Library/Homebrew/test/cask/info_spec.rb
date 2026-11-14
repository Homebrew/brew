# typed: true
# frozen_string_literal: true

require "utils/output"

require "utils"
require "cask/info"

RSpec.describe Cask::Info, :cask do
  let(:args) { Homebrew::Cmd::Info.new([]).args }

  include Utils::Output::Mixin

  def uninstalled(string)
    "#{Tty.bold}#{string}#{Tty.reset}"
  end

  def cannot_install(string)
    "#{Tty.bold}#{string} #{Formatter.error("⊘")}#{Tty.reset}"
  end

  def installed(string)
    "#{Tty.bold}#{string} #{Formatter.success("✔")}#{Tty.reset}"
  end

  def unsatisfied_requirement(string)
    "#{string} #{Formatter.error("✘")}#{Tty.reset}"
  end

  def requirements_section(string)
    <<~EOS.chomp
      #{ohai_title "Requirements"}
      Required: #{string}
    EOS
  end

  def mock_cask_installed(cask_name)
    cask = Cask::CaskLoader.load(cask_name)
    allow(cask).to receive(:installed?).and_return(true)
    allow(Cask::CaskLoader).to receive(:load).and_call_original
    allow(Cask::CaskLoader).to receive(:load).with(cask_name).and_return(cask)
    allow(Cask::Info).to receive(:installation_info).and_wrap_original do |method, arg, **kwargs|
      (arg.token == cask_name) ? "Installed" : method.call(arg, **kwargs)
    end
    (Cask::Caskroom.path/cask_name).mkpath
  end

  before do
    # Prevent unnecessary network requests in `Utils::Analytics.cask_output`
    ENV["HOMEBREW_NO_ANALYTICS"] = "1"
  end

  it "displays some nice info about the specified Cask" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("local-transmission"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("local-transmission")} (Transmission): 2.61
      BitTorrent client
      https://transmissionbt.com/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
      #{requirements_section(installed("macOS >= 11"))}
      ==> Apps
      Transmission.app
    EOS
  end

  it "omits a missing cask name and description" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-depends-on-cask-multiple"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-depends-on-cask-multiple")}: 1.2.3
      #{Formatter.url("https://brew.sh/with-depends-on-cask-multiple")}
      Not installed
      From: #{Formatter.url("https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-depends-on-cask-multiple.rb")}
      #{ohai_title "Dependencies"}
      Required (2): local-caffeine (cask), local-transmission-zip (cask)
      Recursive Runtime (2): 0 installed #{Formatter.success("✔")}, 2 missing #{Formatter.error("✘")}
      #{requirements_section(installed("macOS >= 11"))}
      #{ohai_title "Apps"}
      Caffeine.app
    EOS
  end

  it "lists the aliases of a cask" do
    cask = Cask::CaskLoader.load("local-transmission")
    allow(cask).to receive(:aliases).and_return(["transmission-alias"])

    expect { described_class.info(cask, args:) }.to output(/^Aliases: transmission-alias$/).to_stdout
  end

  it "marks a disabled Cask in the title" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.from_path(cask_path("livecheck/livecheck-disabled")), args:)
    end.to output(
      /#{Regexp.escape(cannot_install("livecheck-disabled"))} #{Regexp.escape(Formatter.error("(disabled)"))}/,
    ).to_stdout
  end

  it "marks a deprecated Cask in the title" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.from_path(cask_path("livecheck/livecheck-deprecated")), args:)
    end.to output(
      /#{Regexp.escape(uninstalled("livecheck-deprecated"))} #{Regexp.escape(Formatter.warning("(deprecated)"))}/,
    ).to_stdout
  end

  it "shows deprecation after the homepage and before installation status" do
    cask = Cask::CaskLoader.load("local-transmission")
    allow(DeprecateDisable).to receive(:message).with(cask) { +"deprecated!\nReplacement:\n  example\n" }

    expect { described_class.info(cask, args:) }.to output(<<~EOS).to_stdout
      ==> local-transmission (Transmission): 2.61
      BitTorrent client
      https://transmissionbt.com/
      Deprecated!
      Replacement:
        example
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
      ==> Requirements
      Required: macOS >= 11
      ==> Apps
      Transmission.app
    EOS
  end

  it "prints inline summary information for casks" do
    cask = Cask::CaskLoader.load("local-transmission")
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    allow(cask).to receive_messages(supports_linux?: false)

    expect { described_class.info(cask, args:) }
      .to output(/Requirements\nRequired: .*macOS >= 11.*✔/).to_stdout
    expect { described_class.info(cask, args:) }.to not_to_output(/==> Name/).to_stdout
    expect { described_class.info(cask, args:) }.to not_to_output(/==> Description/).to_stdout
    expect { described_class.info(cask, args:) }.to not_to_output(/Metadata/).to_stdout
  end

  it "shows installed and available versions when a cask is outdated" do
    cask = Cask::CaskLoader.load("local-transmission")
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    allow(cask).to receive_messages(installed?:        true,
                                    installed_version: "2.60",
                                    outdated?:         true,
                                    version:           Cask::DSL::Version.new("2.61"),
                                    supports_linux?:   false)
    (Cask::Caskroom.path/"local-transmission/2.60").mkpath
    allow(Cask::Caskroom).to receive(:casks).and_return([])
    allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(Cask::Tab.empty)

    expect { described_class.info(cask, args:) }.to output(<<~EOS).to_stdout
      ==> local-transmission #{Formatter.success("↑")} (Transmission): 2.60 → 2.61
      BitTorrent client
      https://transmissionbt.com/
      Installed (as dependency)
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
      ==> Installed Versions
      local-transmission #{Formatter.success("↑")} 2.60 → 2.61 (0B)
      #{requirements_section(installed("macOS >= 11"))}
      ==> Apps
      Transmission.app
    EOS
  end

  describe "installed sibling cask versions" do
    let(:cask) { Cask::Cask.new("example") { version "3.0" } }
    let(:installed_cask) { Cask::Cask.new("example@dev") { version "3.2.0-RC3" } }
    let(:installed_path) { Cask::Caskroom.path/"example@dev/3.2.0-RC3" }
    let(:time) { 1_720_189_863 }

    before do
      installed_path.mkpath
      allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
      allow(installed_cask).to receive_messages(installed?: true, installed_version: "3.2.0-RC3", outdated?: false)
      allow(Cask::Caskroom).to receive(:casks).and_return([installed_cask])
      allow(Cask::Tab).to receive(:for_cask).with(installed_cask).and_return(
        Cask::Tab.new(
          loaded_from_api:          true,
          loaded_from_internal_api: true,
          tabfile:                  TEST_FIXTURE_DIR/"cask_receipt.json",
          time:,
        ),
      )
      allow(Formatter).to receive(:disk_usage_readable).with(0).and_return("844MB")
    end

    it "shows a concise sibling section without --verbose" do
      expected_output = <<~EOS
        #{oh1_title uninstalled("example")}: 3.0
        Not installed
        ==> Installed Versions
        #{installed("example@dev")} 3.2.0-RC3 (844MB)
      EOS
      expect { described_class.info(cask, args:) }
        .to output(expected_output).to_stdout
        .and not_to_output.to_stderr
    end

    it "shows the sibling path and receipt with --verbose" do
      verbose_args = Homebrew::Cmd::Info.new(["--verbose"]).args
      expected_output = <<~EOS
        #{oh1_title uninstalled("example")}: 3.0
        Not installed
        ==> Installed Versions
        #{installed("example@dev")} 3.2.0-RC3 (844MB)
          Caskroom: #{installed_path}
          Installed using the internal formulae.brew.sh API on #{Time.at(time).strftime("%Y-%m-%d at %H:%M:%S")}
      EOS
      expect { described_class.info(cask, args: verbose_args) }
        .to output(expected_output).to_stdout
        .and not_to_output.to_stderr
    end

    it "shows the available version for an outdated sibling" do
      allow(installed_cask).to receive_messages(outdated?: true, version: Cask::DSL::Version.new("4.0"))

      expect { described_class.info(cask, args:) }.to output(<<~EOS).to_stdout
        #{oh1_title uninstalled("example")}: 3.0
        Not installed
        ==> Installed Versions
        example@dev #{Formatter.success("↑")} 3.2.0-RC3 → 4.0 (844MB)
      EOS
    end

    it "shows a missing sibling directory without --verbose" do
      missing_path = Cask::Caskroom.path/"missing-example/3.2.0-RC3"
      allow(installed_cask).to receive(:caskroom_path).and_return(missing_path.parent)

      expect { described_class.info(cask, args:) }.to output(<<~EOS).to_stdout
        #{oh1_title uninstalled("example")}: 3.0
        Not installed
        ==> Installed Versions
        #{installed("example@dev")} 3.2.0-RC3
          #{missing_path} (#{Formatter.error("does not exist")})
      EOS
    end
  end

  it "loads only matching installed casks, including renamed siblings" do
    cask = Cask::Cask.new("example") { version "3.0" }
    tap = Tap.fetch("homebrew/cask")
    allow(Cask::Caskroom).to receive(:tokens).and_return(%w[example@dev old-example unrelated])
    allow(Tap).to receive(:to_a).and_return([tap])
    allow(tap).to receive_messages(cask_alias_table: {},
                                   cask_renames:     { "old-example" => "example@beta" },
                                   tap_migrations:   {})
    expect(Cask::Caskroom).to receive(:casks).with(tokens: %w[example@dev old-example]).and_return([])

    expect { described_class.info(cask, args:) }.to output(<<~EOS).to_stdout
      ==> example: 3.0
      Not installed
    EOS
  end

  it "does not inspect tap renames when no casks are installed" do
    cask = Cask::Cask.new("example") { version "3.0" }
    allow(Cask::Caskroom).to receive(:tokens).and_return([])
    expect(Tap).not_to receive(:to_a)

    expect { described_class.info(cask, args:) }.to output(<<~EOS).to_stdout
      ==> example: 3.0
      Not installed
    EOS
  end

  it "lists an installed cask only once when another tap has the same token" do
    cask = Cask::Cask.new("example", tap: Tap.fetch("other/tools")) { version "2.0" }
    installed_cask = Cask::Cask.new("example", tap: Tap.fetch("original/tools")) { version "1.0" }
    (Cask::Caskroom.path/"example/1.0").mkpath
    allow(cask).to receive_messages(installed?: true, installed_version: "1.0", outdated?: false)
    allow(installed_cask).to receive_messages(installed?: true, installed_version: "1.0", outdated?: false)
    allow(Cask::Caskroom).to receive(:casks).and_return([installed_cask])
    allow(Cask::Tab).to receive(:for_cask).and_return(Cask::Tab.empty)
    allow(described_class).to receive(:repo_url).with(cask).and_return(nil)

    expect { described_class.info(cask, args:) }.to output(<<~EOS).to_stdout
      ==> example: 2.0
      Installed (as dependency)
      ==> Installed Versions
      original/tools/example 1.0 (0B)
    EOS
  end

  describe "a missing installed cask directory" do
    let(:cask) { Cask::Cask.new("example") { version "1.0" } }
    let(:installed_path) { Cask::Caskroom.path/"example/1.0" }
    let(:time) { 1_720_189_863 }

    before do
      allow(cask).to receive_messages(installed?: true, installed_version: "1.0", outdated?: false)
      allow(Cask::Caskroom).to receive(:casks).and_return([])
      allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(
        Cask::Tab.new(loaded_from_api: true, tabfile: TEST_FIXTURE_DIR/"cask_receipt.json", time:),
      )
    end

    it "shows the missing path without --verbose" do
      expect { described_class.info(cask, args:) }.to output(<<~EOS).to_stdout
        ==> example: 1.0
        Installed (as dependency)
        ==> Installed Versions
        example 1.0
          #{installed_path} (does not exist)
      EOS
    end

    it "shows the missing path once and the receipt with --verbose" do
      verbose_args = Homebrew::Cmd::Info.new(["--verbose"]).args
      expect { described_class.info(cask, args: verbose_args) }.to output(<<~EOS).to_stdout
        ==> example: 1.0
        Installed (as dependency)
        ==> Installed Versions
        example 1.0
          #{installed_path} (does not exist)
          Installed using the formulae.brew.sh API on #{Time.at(time).strftime("%Y-%m-%d at %H:%M:%S")}
      EOS
    end
  end

  describe "complete cask information" do
    let(:cask) { Cask::CaskLoader.load("with-binary") }
    let(:installed_path) { Cask::Caskroom.path/"with-binary/1.2.3" }

    before do
      installed_path.mkpath
      allow(cask).to receive_messages(installed?: true, installed_version: "1.2.3", outdated?: false)
      allow(Cask::Caskroom).to receive(:casks).and_return([])
      allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(Cask::Tab.empty)
    end

    context "without --verbose" do
      it "prints the complete output" do
        expected_output = <<~EOS
          ==> with-binary (With Binary): 1.2.3
          Cask with a binary stanza
          https://brew.sh/with-binary
          Installed (as dependency)
          From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-binary.rb
          ==> Installed Versions
          with-binary 1.2.3 (0B)
          ==> Apps
          App.app
        EOS
        expect { described_class.info(cask, args:) }
          .to output(expected_output).to_stdout
          .and not_to_output.to_stderr
      end
    end

    context "with --verbose" do
      let(:args) { Homebrew::Cmd::Info.new(["--verbose"]).args }

      it "prints the complete output" do
        expected_output = <<~EOS
          ==> with-binary (With Binary): 1.2.3
          Cask with a binary stanza
          https://brew.sh/with-binary
          Installed (as dependency)
          From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-binary.rb
          ==> Installed Versions
          with-binary 1.2.3 (0B)
            Caskroom: #{installed_path}
          ==> Apps
          App.app
          ==> Binaries
          binary
        EOS
        expect { described_class.info(cask, args:) }
          .to output(expected_output).to_stdout
          .and not_to_output.to_stderr
      end
    end
  end

  it "groups artifacts by type and retains target and plugin details" do
    cask = Cask::Cask.new("grouped-artifacts") do
      version "1.0"
      sha256 :no_check
      url "https://example.com/grouped-artifacts.zip"
      app "Example.app", target: "Renamed.app"
      font "First.ttf"
      font "Second.ttf", target: "Renamed.ttf"
      manpage "example.1"
      audio_unit_plugin "Example.component"
      colorpicker "Example.colorPicker"
      internet_plugin "Example.plugin"
      vst_plugin "Example.vst"
      vst3_plugin "Example.vst3"
      qlplugin "Example.qlgenerator"
      pkg "Example.pkg"
      binary "example"
    end
    allow(Cask::Caskroom).to receive(:casks).and_return([])

    expected_output = <<~EOS
      ==> grouped-artifacts: 1.0
      Not installed
      ==> Apps
      Example.app -> Renamed.app
      ==> Fonts
      First.ttf
      Second.ttf -> Renamed.ttf
      ==> Manpages
      example.1
      ==> Plugins
      Example.component (Audio Unit Plugin)
      Example.colorPicker (Colorpicker)
      Example.plugin (Internet Plugin)
      Example.vst (VST Plugin)
      Example.vst3 (VST3 Plugin)
      Example.qlgenerator (Quick Look Plugin)
      ==> Artifacts
      Example.pkg (Pkg)
      ==> Binaries
      example
    EOS
    expect { described_class.info(cask, args: Homebrew::Cmd::Info.new(["--verbose"]).args) }
      .to output(expected_output).to_stdout
  end

  it "lists command wrappers under Binaries only with --verbose" do
    cask = Cask::Cask.new("with-command-wrapper") do
      version "1.2.3"
      sha256 :no_check
      url "file://#{TEST_FIXTURE_DIR}/cask/container.zip"
      command_wrapper "example", content: "#!/bin/sh\n"
    end
    expect(described_class.get_info(cask)).not_to include("==> Artifacts", "==> Binaries", "Command Wrapper")
    verbose_info = described_class.get_info(cask, verbose: true)
    expect(verbose_info).to include("==> Binaries\nexample\n")
    expect(verbose_info).not_to include("==> Artifacts", "Command Wrapper")
  end

  it "prints cask dependencies if the Cask has any" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    mock_cask_installed("local-transmission-zip")
    expect do
      described_class.info(Cask::CaskLoader.load("with-depends-on-cask-multiple"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-depends-on-cask-multiple")}: 1.2.3
      #{Formatter.url("https://brew.sh/with-depends-on-cask-multiple")}
      Not installed
      From: #{Formatter.url("https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-depends-on-cask-multiple.rb")}
      #{ohai_title "Dependencies"}
      Required (2): local-caffeine (cask), #{installed("local-transmission-zip (cask)")}
      Recursive Runtime (2): 1 installed #{Formatter.success("✔")}, 1 missing #{Formatter.error("✘")}
      #{requirements_section(installed("macOS >= 11"))}
      #{ohai_title "Apps"}
      Caffeine.app
    EOS
  end

  it "summarises recursive runtime dependencies as all installed when none are missing" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    mock_cask_installed("local-caffeine")
    mock_cask_installed("local-transmission-zip")
    expect do
      described_class.info(Cask::CaskLoader.load("with-depends-on-cask-multiple"), args:)
    end.to output(/Recursive Runtime \(2\): all installed #{Formatter.success("✔")}/).to_stdout
  end

  it "prints cask and formulas dependencies if the Cask has both" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    arch_requirements = if Hardware::CPU.arm?
      "#{unsatisfied_requirement("x86_64 architecture")}, #{installed("arm64 architecture")}"
    else
      "#{installed("x86_64 architecture")}, #{unsatisfied_requirement("arm64 architecture")}"
    end

    expect do
      described_class.info(Cask::CaskLoader.load("with-depends-on-everything"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-depends-on-everything")}: 1.2.3
      #{Formatter.url("https://brew.sh/with-depends-on-everything")}
      Not installed
      From: #{Formatter.url("https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-depends-on-everything.rb")}
      #{ohai_title "Dependencies"}
      Required (3): unar, local-caffeine (cask), with-depends-on-cask (cask)
      Recursive Runtime (4): 0 installed #{Formatter.success("✔")}, 4 missing #{Formatter.error("✘")}
      #{requirements_section("#{arch_requirements}, #{installed("macOS >= 11")}")}
      #{ohai_title "Apps"}
      Caffeine.app
    EOS
  end

  it "marks an unsatisfied requirement on an uninstalled cask" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    unsatisfied_arch = Hardware::CPU.arm? ? "x86_64" : "arm64"

    expect { described_class.info(Cask::CaskLoader.load("with-depends-on-everything"), args:) }
      .to output(/Required: .*#{unsatisfied_arch} architecture.*✘/).to_stdout
  end

  it "prints auto_updates if the Cask has `auto_updates true`" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-auto-updates"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-auto-updates")} (AutoUpdates): 1.0 (auto_updates)
      https://brew.sh/autoupdates
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-auto-updates.rb
      #{requirements_section(installed("macOS >= 11"))}
      ==> Apps
      AutoUpdates.app
    EOS
  end

  it "prints pinned cask metadata" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)
    cask.pin

    expect { described_class.info(cask, args:) }
      .to output(%r{
        From:\ https://github\.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-caffeine\.rb\n
        Pinned:\ 1\.2\.3\ on\ \d{4}-\d{2}-\d{2}\ at\ \d{2}:\d{2}:\d{2}\n
        ==>\ Installed\ Versions
      }x).to_stdout

    cask.unpin
  end

  it "prints caveats if the Cask provided one" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-caveats"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-caveats")}: 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-caveats.rb
      #{requirements_section(installed("macOS >= 11"))}
      ==> Apps
      Caffeine.app
      ==> Caveats
      Here are some things you might want to know.

      Cask token: with-caveats

      Custom text via puts followed by DSL-generated text:
      To use with-caveats, you may need to add the /custom/path/bin directory
      to your PATH environment variable, e.g. (for Bash shell):
        export PATH=/custom/path/bin:"$PATH"

    EOS
  end

  it 'does not print "Caveats" section divider if the caveats block has no output' do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-conditional-caveats"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-conditional-caveats")}: 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-conditional-caveats.rb
      #{requirements_section(installed("macOS >= 11"))}
      ==> Apps
      Caffeine.app
    EOS
  end

  it "prints languages specified in the Cask" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-languages"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-languages")} (Caffeine): 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-languages.rb
      #{requirements_section(installed("macOS >= 11"))}
      ==> Languages
      zh, en-US
      ==> Apps
      Caffeine.app
    EOS
  end

  it 'does not print "Languages" section divider if the languages block has no output' do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("without-languages"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("without-languages")}: 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/without-languages.rb
      #{requirements_section(installed("macOS >= 11"))}
      ==> Apps
      Caffeine.app
    EOS
  end

  it "prints install information for an installed Cask loaded from the API" do
    mktmpdir do |caskroom|
      verbose_args = Homebrew::Cmd::Info.new(["--verbose"]).args
      FileUtils.mkdir caskroom/"2.61"

      cask = Cask::CaskLoader.load("local-transmission")
      time = 1_720_189_863
      tab = Cask::Tab.new(
        loaded_from_api:      true,
        installed_on_request: false,
        tabfile:              TEST_FIXTURE_DIR/"cask_receipt.json",
        time:,
      )
      expect(cask).to receive(:caskroom_path).and_return(caskroom)
      allow(cask).to receive_messages(installed?: true, outdated?: false, installed_version: "2.61")
      allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(tab)
      allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

      expect do
        described_class.info(cask, args: verbose_args)
      end.to output(<<~EOS).to_stdout
        ==> #{installed("local-transmission")} (Transmission): 2.61
        BitTorrent client
        https://transmissionbt.com/
        Installed (as dependency)
        From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
        ==> Installed Versions
        #{installed("local-transmission")} 2.61 (0B)
          Caskroom: #{caskroom}/2.61
          Installed using the formulae.brew.sh API on #{Time.at(time).strftime("%Y-%m-%d at %H:%M:%S")}
        #{requirements_section(installed("macOS >= 11"))}
        ==> Apps
        Transmission.app
      EOS
    end
  end

  it "prints install information for an installed Cask loaded from the internal API" do
    mktmpdir do |caskroom|
      verbose_args = Homebrew::Cmd::Info.new(["--verbose"]).args
      FileUtils.mkdir caskroom/"2.61"

      cask = Cask::CaskLoader.load("local-transmission")
      time = 1_720_189_863
      tab = Cask::Tab.new(
        loaded_from_api:          true,
        loaded_from_internal_api: true,
        tabfile:                  TEST_FIXTURE_DIR/"cask_receipt.json",
        time:,
      )
      expect(cask).to receive(:caskroom_path).and_return(caskroom)
      allow(cask).to receive_messages(installed?: true, outdated?: false, installed_version: "2.61")
      allow(Cask::Tab).to receive(:for_cask).with(cask).and_return(tab)
      allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

      expect do
        described_class.info(cask, args: verbose_args)
      end.to output(<<~EOS).to_stdout
        ==> #{installed("local-transmission")} (Transmission): 2.61
        BitTorrent client
        https://transmissionbt.com/
        Installed (as dependency)
        From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
        ==> Installed Versions
        #{installed("local-transmission")} 2.61 (0B)
          Caskroom: #{caskroom}/2.61
          Installed using the internal formulae.brew.sh API on #{Time.at(time).strftime("%Y-%m-%d at %H:%M:%S")}
        #{requirements_section(installed("macOS >= 11"))}
        ==> Apps
        Transmission.app
      EOS
    end
  end

  it "omits binary-only artifacts without --verbose" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-non-executable-binary"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-non-executable-binary")}: 1.2.3
      https://brew.sh/with-binary
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-non-executable-binary.rb
    EOS
  end

  it "shows binary-only artifacts under Binaries with --verbose" do
    verbose_args = Homebrew::Cmd::Info.new(["--verbose"]).args
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-non-executable-binary"), args: verbose_args)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-non-executable-binary")}: 1.2.3
      https://brew.sh/with-binary
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-non-executable-binary.rb
      ==> Binaries
      naked_non_executable
    EOS
  end
end
