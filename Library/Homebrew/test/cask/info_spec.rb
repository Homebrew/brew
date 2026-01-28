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

  def mock_cask_installed(cask_name)
    cask = Cask::CaskLoader.load(cask_name)
    allow(cask).to receive(:installed?).and_return(true)
    allow(Cask::CaskLoader).to receive(:load).and_call_original
    allow(Cask::CaskLoader).to receive(:load).with(cask_name).and_return(cask)
    allow(described_class).to receive(:installation_info).and_wrap_original do |method, arg, **kwargs|
      (arg.token == cask_name) ? "Installed" : method.call(arg, **kwargs)
    end
  end

  before do
    # Prevent unnecessary network requests in `Utils::Analytics.cask_output`
    ENV["HOMEBREW_NO_ANALYTICS"] = "1"
  end

  it "displays some nice info about the specified Cask" do
    expect do
      described_class.info(Cask::CaskLoader.load("local-transmission"), args:)
    end.to output(<<~EOS).to_stdout
      ==> local-transmission: 2.61
      https://transmissionbt.com/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
      ==> Name
      Transmission
      ==> Description
      BitTorrent client
      ==> Artifacts
      Transmission.app (App)
    EOS
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
      #{ohai_title "Name"}
      #{Formatter.error("None")}
      #{ohai_title "Description"}
      #{Formatter.error("None")}
      #{ohai_title "Dependencies"}
      #{uninstalled("local-caffeine (cask)")}, #{installed("local-transmission-zip (cask)")}
      #{ohai_title "Artifacts"}
      Caffeine.app (App)
    EOS
  end

  it "prints cask and formulas dependencies if the Cask has both" do
    allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)
    expect do
      described_class.info(Cask::CaskLoader.load("with-depends-on-everything"), args:)
    end.to output(<<~EOS).to_stdout
      #{oh1_title uninstalled("with-depends-on-everything")}: 1.2.3
      #{Formatter.url("https://brew.sh/with-depends-on-everything")}
      Not installed
      From: #{Formatter.url("https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-depends-on-everything.rb")}
      #{ohai_title "Name"}
      #{Formatter.error("None")}
      #{ohai_title "Description"}
      #{Formatter.error("None")}
      #{ohai_title "Dependencies"}
      #{uninstalled("unar")}, #{uninstalled("local-caffeine (cask)")}, #{uninstalled("with-depends-on-cask (cask)")}
      #{ohai_title "Artifacts"}
      Caffeine.app (App)
    EOS
  end

  it "prints auto_updates if the Cask has `auto_updates true`" do
    expect do
      described_class.info(Cask::CaskLoader.load("with-auto-updates"), args:)
    end.to output(<<~EOS).to_stdout
      ==> with-auto-updates: 1.0 (auto_updates)
      https://brew.sh/autoupdates
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-auto-updates.rb
      ==> Name
      AutoUpdates
      ==> Description
      None
      ==> Artifacts
      AutoUpdates.app (App)
    EOS
  end

  it "prints caveats if the Cask provided one" do
    expect do
      described_class.info(Cask::CaskLoader.load("with-caveats"), args:)
    end.to output(<<~EOS).to_stdout
      ==> with-caveats: 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-caveats.rb
      ==> Name
      None
      ==> Description
      None
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
    expect do
      described_class.info(Cask::CaskLoader.load("with-conditional-caveats"), args:)
    end.to output(<<~EOS).to_stdout
      ==> with-conditional-caveats: 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-conditional-caveats.rb
      ==> Name
      None
      ==> Description
      None
      ==> Artifacts
      Caffeine.app (App)
    EOS
  end

  it "prints languages specified in the Cask" do
    expect do
      described_class.info(Cask::CaskLoader.load("with-languages"), args:)
    end.to output(<<~EOS).to_stdout
      ==> with-languages: 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/with-languages.rb
      ==> Name
      None
      ==> Description
      None
      ==> Languages
      zh, en-US
      ==> Artifacts
      Caffeine.app (App)
    EOS
  end

  it 'does not print "Languages" section divider if the languages block has no output' do
    expect do
      described_class.info(Cask::CaskLoader.load("without-languages"), args:)
    end.to output(<<~EOS).to_stdout
      ==> without-languages: 1.2.3
      https://brew.sh/
      Not installed
      From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/w/without-languages.rb
      ==> Name
      None
      ==> Description
      None
      ==> Artifacts
      Caffeine.app (App)
    EOS
  end

  it "prints install information for an installed Cask" do
    mktmpdir do |caskroom|
      FileUtils.mkdir caskroom/"2.61"

      cask = Cask::CaskLoader.load("local-transmission")
      time = 1_720_189_863
      tab = Cask::Tab.new(loaded_from_api: true, tabfile: TEST_FIXTURE_DIR/"cask_receipt.json", time:)
      expect(cask).to receive(:installed?).and_return(true)
      expect(cask).to receive(:caskroom_path).and_return(caskroom)
      expect(cask).to receive(:installed_version).and_return("2.61")
      expect(Cask::Tab).to receive(:for_cask).with(cask).and_return(tab)
      allow_any_instance_of(StringIO).to receive(:tty?).and_return(true)

      expect do
        described_class.info(cask, args:)
      end.to output(<<~EOS).to_stdout
        ==> #{installed("local-transmission")}: 2.61
        https://transmissionbt.com/
        Installed
        #{caskroom}/2.61 (0B)
          Installed using the formulae.brew.sh API on #{Time.at(time).strftime("%Y-%m-%d at %H:%M:%S")}
        From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/l/local-transmission.rb
        ==> Name
        Transmission
        ==> Description
        BitTorrent client
        ==> Artifacts
        Transmission.app (App)
      EOS
    end
  end
end
