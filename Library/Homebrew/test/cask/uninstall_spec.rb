# frozen_string_literal: true

require "cask/uninstall"

RSpec.describe Cask::Uninstall, :cask do
  it "displays the uninstallation progress" do
    caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

    Cask::Installer.new(caffeine).install

    output = Regexp.new <<~EOS
      ==> Uninstalling Cask local-caffeine
      ==> Backing App 'Caffeine.app' up to '.*Caffeine.app'
      ==> Removing App '.*Caffeine.app'
      ==> Purging files for version 1.2.3 of Cask local-caffeine
    EOS

    expect do
      described_class.uninstall_casks(caffeine)
    end.to output(output).to_stdout
  end

  it "shows an error when a Cask is provided that's not installed" do
    caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

    expect { described_class.uninstall_casks(caffeine) }
      .to raise_error(Cask::CaskNotInstalledError, /is not installed/)
  end

  it "tries anyway on a non-present Cask when --force is given" do
    caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

    expect do
      described_class.uninstall_casks(caffeine, force: true)
    end.not_to raise_error
  end

  it "can uninstall and unlink multiple Casks at once" do
    caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))
    transmission = Cask::CaskLoader.load(cask_path("local-transmission"))

    Cask::Installer.new(caffeine).install
    Cask::Installer.new(transmission).install

    expect(caffeine).to be_installed
    expect(transmission).to be_installed

    described_class.uninstall_casks(caffeine, transmission)

    expect(caffeine).not_to be_installed
    expect(caffeine.config.appdir.join("Transmission.app")).not_to exist
    expect(transmission).not_to be_installed
    expect(transmission.config.appdir.join("Caffeine.app")).not_to exist
  end

  it "can uninstall Casks when the uninstall script is missing, but only when using `--force`" do
    cask = Cask::CaskLoader.load(cask_path("with-uninstall-script-app"))

    Cask::Installer.new(cask).install

    expect(cask).to be_installed

    FileUtils.rm_r(cask.config.appdir.join("MyFancyApp.app"))

    expect { described_class.uninstall_casks(cask) }
      .to raise_error(Cask::CaskError, /uninstall script .* does not exist/)

    expect(cask).to be_installed

    expect do
      described_class.uninstall_casks(cask, force: true)
    end.not_to raise_error

    expect(cask).not_to be_installed
  end

  describe "when multiple versions of a cask are installed" do
    let(:token) { "versioned-cask" }
    let(:first_installed_version) { "1.2.3" }
    let(:last_installed_version) { "4.5.6" }
    let(:timestamped_versions) do
      [
        [first_installed_version, "123000"],
        [last_installed_version,  "456000"],
      ]
    end
    let(:caskroom_path) { Cask::Caskroom.path.join(token).tap(&:mkpath) }

    before do
      timestamped_versions.each do |timestamped_version|
        caskroom_path.join(".metadata", *timestamped_version, "Casks").tap(&:mkpath)
                     .join("#{token}.rb").open("w") do |caskfile|
                       caskfile.puts <<~RUBY
                         cask '#{token}' do
                           version '#{timestamped_version[0]}'
                         end
                       RUBY
                     end
        caskroom_path.join(timestamped_version[0]).mkpath
      end
    end

    it "uninstalls one version at a time" do
      described_class.uninstall_casks(Cask::Cask.new("versioned-cask"))

      expect(caskroom_path.join(first_installed_version)).to exist
      expect(caskroom_path.join(last_installed_version)).not_to exist
      expect(caskroom_path).to exist

      described_class.uninstall_casks(Cask::Cask.new("versioned-cask"))

      expect(caskroom_path.join(first_installed_version)).not_to exist
      expect(caskroom_path).not_to exist
    end
  end

  context "when Casks in Taps have been renamed or removed" do
    let(:app) { Cask::Config.new.appdir.join("ive-been-renamed.app") }
    let(:caskroom_path) { Cask::Caskroom.path.join("ive-been-renamed").tap(&:mkpath) }
    let(:saved_caskfile) do
      caskroom_path.join(".metadata", "latest", "timestamp", "Casks").join("ive-been-renamed.rb")
    end

    before do
      app.tap(&:mkpath)
         .join("Contents").tap(&:mkpath)
         .join("Info.plist").tap { FileUtils.touch(_1) }

      caskroom_path.mkpath

      saved_caskfile.dirname.mkpath

      File.write saved_caskfile, <<~RUBY
        cask 'ive-been-renamed' do
          version :latest

          app 'ive-been-renamed.app'
        end
      RUBY
    end

    it "can still uninstall them" do
      described_class.uninstall_casks(Cask::Cask.new("ive-been-renamed"))

      expect(app).not_to exist
      expect(caskroom_path).not_to exist
    end
  end
end
