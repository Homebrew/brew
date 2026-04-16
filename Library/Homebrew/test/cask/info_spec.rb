# typed: false
# frozen_string_literal: true

require "utils"
require "cask/info"

RSpec.describe Cask::Info, :cask do
  include Utils::Output::Mixin

  let(:args) { instance_double(Homebrew::Cmd::Info::Args) }

  def uninstalled(string)
    "#{Tty.bold}#{string} #{Formatter.error("✘")}#{Tty.reset}"
  end

  def installed(string)
    "#{Tty.bold}#{string} #{Formatter.success("✔")}#{Tty.reset}"
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
    allow(described_class).to receive(:installation_info).and_wrap_original do |method, arg, **kwargs|
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
      #{requirements_section(installed("macOS >= 10.15"))}
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
      Required (2): #{uninstalled("local-caffeine (cask)")}, #{uninstalled("local-transmission-zip (cask)")}
      Recursive Runtime (2): 0 #{Formatter.success("✔")}, 2 #{Formatter.error("✘")}
      #{requirements_section(installed("macOS >= 10.15"))}
      #{ohai_title "Artifacts"}
      Caffeine.app (App)
    EOS
  end

  it "prints inline summary information for casks" do
    cask = Cask::CaskLoader.load("local-transmission")
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    allow(cask).to receive_messages(supports_linux?: false)

    expect { described_class.info(cask, args:) }
      .to output(/Requirements\nRequired: .*macOS >= 10\.15.*✔/).to_stdout
    expect { described_class.info(cask, args:) }.to not_to_output(/==> Name/).to_stdout
    expect { described_class.info(cask, args:) }.to not_to_output(/==> Description/).to_stdout
    expect { described_class.info(cask, args:) }.to not_to_output(/Metadata/).to_stdout
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
      Required (2): #{uninstalled("local-caffeine (cask)")}, #{installed("local-transmission-zip (cask)")}
      Recursive Runtime (2): 1 #{Formatter.success("✔")}, 1 #{Formatter.error("✘")}
      #{requirements_section(installed("macOS >= 10.15"))}
      #{ohai_title "Artifacts"}
      Caffeine.app (App)
    EOS
  end

  it "prints cask and formulas dependencies if the Cask has both" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    arch_requirements = if Hardware::CPU.arm?
      "#{uninstalled("x86_64 architecture")}, #{installed("arm64 architecture")}"
    else
      "#{installed("x86_64 architecture")}, #{uninstalled("arm64 architecture")}"
    end

    expect do
      described_class.info(Cask::CaskLoader.load("with-depends-on-everything"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-depends-on-everything")}: 1.2.3
      #{Formatter.url("https://brew.sh/with-depends-on-everything")}
      Not installed
      From: #{Formatter.url("https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-depends-on-everything.rb")}
      #{ohai_title "Dependencies"}
      Required (3): #{uninstalled("unar")}, #{uninstalled("local-caffeine (cask)")}, #{uninstalled("with-depends-on-cask (cask)")}
      Recursive Runtime (4): 0 #{Formatter.success("✔")}, 4 #{Formatter.error("✘")}
      #{requirements_section("#{arch_requirements}, #{installed("macOS >= 10.15")}")}
      #{ohai_title "Artifacts"}
      Caffeine.app (App)
    EOS
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
      #{requirements_section(installed("macOS >= 10.15"))}
      ==> Artifacts
      AutoUpdates.app (App)
    EOS
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
      #{requirements_section(installed("macOS >= 10.15"))}
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
      #{requirements_section(installed("macOS >= 10.15"))}
      ==> Artifacts
      Caffeine.app (App)
    EOS
  end

  it "prints languages specified in the Cask" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

    expect do
      described_class.info(Cask::CaskLoader.load("with-languages"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-languages")}: 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-languages.rb
      #{requirements_section(installed("macOS >= 10.15"))}
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
      #{requirements_section(installed("macOS >= 10.15"))}
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
        loaded_from_api:         true,
        installed_as_dependency: true,
        tabfile:                 TEST_FIXTURE_DIR/"cask_receipt.json",
        time:,
      )
      allow(cask).to receive(:installed?).and_return(true)
      expect(cask).to receive(:caskroom_path).and_return(caskroom)
      expect(cask).to receive(:installed_version).and_return("2.61")
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
        #{requirements_section(installed("macOS >= 10.15"))}
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
      allow(cask).to receive(:installed?).and_return(true)
      expect(cask).to receive(:caskroom_path).and_return(caskroom)
      expect(cask).to receive(:installed_version).and_return("2.61")
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
        #{requirements_section(installed("macOS >= 10.15"))}
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
      #{requirements_section(installed("macOS >= 10.15 (or Linux)"))}
      ==> Artifacts
      naked_non_executable (Binary)
    EOS
  end
end
