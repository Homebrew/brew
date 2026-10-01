# typed: true
# frozen_string_literal: true

require "utils/output"

require "utils"
require "cask/info"

RSpec.describe Cask::Info, :cask do
  let(:args) { instance_double(Homebrew::Cmd::Info::Args) }

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
      ==> Artifacts
      Transmission.app (App)
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
      #{ohai_title "Artifacts"}
      Caffeine.app (App)
    EOS
  end

  it "marks a disabled Cask in the title" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load(cask_path("livecheck/livecheck-disabled")), args:)
    end.to output(
      /#{Regexp.escape(cannot_install("livecheck-disabled"))} #{Regexp.escape(Formatter.error("(disabled)"))}/,
    ).to_stdout
  end

  it "marks a deprecated Cask in the title" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load(cask_path("livecheck/livecheck-deprecated")), args:)
    end.to output(
      /#{Regexp.escape(uninstalled("livecheck-deprecated"))} #{Regexp.escape(Formatter.warning("(deprecated)"))}/,
    ).to_stdout
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

    expect { described_class.info(cask, args:) }
      .to output(/==> .*↑.*: 2\.60 → 2\.61/).to_stdout
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
      #{ohai_title "Artifacts"}
      Caffeine.app (App)
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
      #{ohai_title "Artifacts"}
      Caffeine.app (App)
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
      ==> Artifacts
      AutoUpdates.app (App)
    EOS
  end

  it "prints pinned cask metadata" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    cask = Cask::CaskLoader.load("local-caffeine")
    InstallHelper.stub_cask_installation(cask)
    cask.pin

    expect { described_class.info(cask, args:) }
      .to output(/Pinned: 1\.2\.3 on \d{4}-\d{2}-\d{2} at \d{2}:\d{2}:\d{2}/).to_stdout

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
      ==> Artifacts
      Caffeine.app (App)
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
      ==> Artifacts
      Caffeine.app (App)
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
      ==> Artifacts
      Caffeine.app (App)
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
      ==> Artifacts
      Caffeine.app (App)
    EOS
  end

  it "prints install information for an installed Cask loaded from the API" do
    mktmpdir do |caskroom|
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
        described_class.info(cask, args:)
      end.to output(<<~EOS).to_stdout
        ==> #{installed("local-transmission")} (Transmission): 2.61
        BitTorrent client
        https://transmissionbt.com/
        Installed (as dependency)
        #{caskroom}/2.61 (0B)
          Installed using the formulae.brew.sh API on #{Time.at(time).strftime("%Y-%m-%d at %H:%M:%S")}
        From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
        #{requirements_section(installed("macOS >= 11"))}
        ==> Artifacts
        Transmission.app (App)
      EOS
    end
  end

  it "prints install information for an installed Cask loaded from the internal API" do
    mktmpdir do |caskroom|
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
        described_class.info(cask, args:)
      end.to output(<<~EOS).to_stdout
        ==> #{installed("local-transmission")} (Transmission): 2.61
        BitTorrent client
        https://transmissionbt.com/
        Installed (as dependency)
        #{caskroom}/2.61 (0B)
          Installed using the internal formulae.brew.sh API on #{Time.at(time).strftime("%Y-%m-%d at %H:%M:%S")}
        From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
        #{requirements_section(installed("macOS >= 11"))}
        ==> Artifacts
        Transmission.app (App)
      EOS
    end
  end

  it "shows requirements" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-non-executable-binary"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-non-executable-binary")}: 1.2.3
      https://brew.sh/with-binary
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-non-executable-binary.rb
      ==> Artifacts
      naked_non_executable (Binary)
    EOS
  end
end
