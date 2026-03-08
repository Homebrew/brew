# typed: true
# frozen_string_literal: true

require "cask/installer"
require "cask/reinstall"

RSpec.describe Cask::Reinstall, :cask do
  it "displays the reinstallation progress" do
    caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

    Cask::Installer.new(caffeine).install

    output = Regexp.new <<~EOS
      ==> Fetching downloads for:.*caffeine
      ==> Uninstalling Cask local-caffeine
      ==> Backing App 'Caffeine.app' up to '.*Caffeine.app'
      ==> Removing App '.*Caffeine.app'
      ==> Purging files for version 1.2.3 of Cask local-caffeine
      ==> Installing Cask local-caffeine
      ==> Moving App 'Caffeine.app' to '.*Caffeine.app'
      .*local-caffeine was successfully installed!
    EOS

    expect do
      described_class.reinstall_casks(Cask::CaskLoader.load("local-caffeine"))
    end.to output(output).to_stdout
  end

  it "displays the reinstallation progress with zapping" do
    caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

    Cask::Installer.new(caffeine).install

    output = Regexp.new <<~EOS
      ==> Fetching downloads for:.*caffeine
      ==> Backing App 'Caffeine.app' up to '.*Caffeine.app'
      ==> Removing App '.*Caffeine.app'
      ==> Dispatching zap stanza
      ==> Trashing files:
      .*org.example.caffeine.plist
      ==> Removing all staged versions of Cask 'local-caffeine'
      ==> Installing Cask local-caffeine
      ==> Moving App 'Caffeine.app' to '.*Caffeine.app'
      .*local-caffeine was successfully installed!
    EOS

    expect do
      described_class.reinstall_casks(Cask::CaskLoader.load("local-caffeine"), zap: true)
    end.to output(output).to_stdout
  end

  it "allows reinstalling a Cask" do
    Cask::Installer.new(Cask::CaskLoader.load(cask_path("local-transmission-zip"))).install

    expect(Cask::CaskLoader.load(cask_path("local-transmission-zip"))).to be_installed

    described_class.reinstall_casks(Cask::CaskLoader.load("local-transmission-zip"))
    expect(Cask::CaskLoader.load(cask_path("local-transmission-zip"))).to be_installed
  end

  it "continues reinstalling remaining casks when one raises" do
    cask1 = Cask::CaskLoader.load(cask_path("local-caffeine"))
    cask2 = Cask::CaskLoader.load(cask_path("local-transmission-zip"))

    Cask::Installer.new(cask1).install
    Cask::Installer.new(cask2).install

    failing_installer = instance_double(Cask::Installer)
    allow(failing_installer).to receive(:prelude)
    allow(failing_installer).to receive(:enqueue_downloads)
    allow(failing_installer).to receive(:install).and_raise(Cask::CaskError.new("reinstall failed"))

    successful_installer = instance_double(Cask::Installer)
    allow(successful_installer).to receive(:prelude)
    allow(successful_installer).to receive(:enqueue_downloads)

    allow(Cask::Installer).to receive(:new).and_return(failing_installer, successful_installer)

    expect(successful_installer).to receive(:install)
    expect { described_class.reinstall_casks(cask1, cask2) }.to raise_error(Cask::CaskError, "reinstall failed")
  end

  it "allows reinstalling a non installed Cask" do
    expect(Cask::CaskLoader.load(cask_path("local-transmission-zip"))).not_to be_installed

    described_class.reinstall_casks(Cask::CaskLoader.load("local-transmission-zip"))
    expect(Cask::CaskLoader.load(cask_path("local-transmission-zip"))).to be_installed
  end
end
