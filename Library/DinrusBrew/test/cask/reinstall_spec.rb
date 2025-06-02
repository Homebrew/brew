# frozen_string_literal: true

require "cask/installer"
require "cask/reinstall"

RSpec.describe Cask::Reinstall, :cask do
  it "displays the reinstallation progress" do
    caffeine = Cask::CaskLoader.load(cask_path("local-caffeine"))

    Cask::Installer.new(caffeine).install

    output = Regexp.new <<~EOS
      ==> Downloading file:.*caffeine.zip
      Already downloaded: .*--caffeine.zip
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
      ==> Downloading file:.*caffeine.zip
      Already downloaded: .*--caffeine.zip
      ==> Implied `brew uninstall --cask local-caffeine`
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
    Cask::Installer.new(Cask::CaskLoader.load(cask_path("local-transmission"))).install

    expect(Cask::CaskLoader.load(cask_path("local-transmission"))).to be_installed

    described_class.reinstall_casks(Cask::CaskLoader.load("local-transmission"))
    expect(Cask::CaskLoader.load(cask_path("local-transmission"))).to be_installed
  end

  it "allows reinstalling a non installed Cask" do
    expect(Cask::CaskLoader.load(cask_path("local-transmission"))).not_to be_installed

    described_class.reinstall_casks(Cask::CaskLoader.load("local-transmission"))
    expect(Cask::CaskLoader.load(cask_path("local-transmission"))).to be_installed
  end
end
