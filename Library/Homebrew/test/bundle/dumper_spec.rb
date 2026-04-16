# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/dumper"
require "bundle/brew_services"
require "cask"

RSpec.describe Homebrew::Bundle::Dumper do
  subject(:dumper) { described_class }

  before do
    ENV["HOMEBREW_BUNDLE_FILE"] = ""

    allow(Homebrew::Bundle).to receive(:cask_installed?).and_return(true)
    allow(Homebrew::Bundle::MacAppStore).to receive(:package_manager_executable).and_return(nil)
    allow(Homebrew::Bundle::VscodeExtension).to receive(:package_manager_executable).and_return(nil)
    Homebrew::Bundle::Brew.reset!
    Homebrew::Bundle::Tap.reset!
    Homebrew::Bundle::Cask.reset!
    Homebrew::Bundle::MacAppStore.reset!
    Homebrew::Bundle::VscodeExtension.reset!
    Homebrew::Bundle::Go.reset!
    Homebrew::Bundle::Cargo.reset!
    Homebrew::Bundle::Uv.reset!
    Homebrew::Bundle::Brew::Services.reset!

    chrome     = instance_double(Cask::Cask,
                                 full_name: "google-chrome",
                                 to_s:      "google-chrome",
                                 config:    nil)
    java       = instance_double(Cask::Cask,
                                 full_name: "java",
                                 to_s:      "java",
                                 config:    nil)
    iterm2beta = instance_double(Cask::Cask,
                                 full_name: "homebrew/cask-versions/iterm2-beta",
                                 to_s:      "iterm2-beta",
                                 config:    nil)

    allow(Cask::Caskroom).to receive(:casks).and_return([chrome, java, iterm2beta])
    allow(Homebrew::Bundle::Go).to receive_messages(package_manager_executable: nil, "`": "")
    allow(Homebrew::Bundle::Cargo).to receive_messages(package_manager_executable: nil, "`": "")
    allow(Homebrew::Bundle::Uv).to receive_messages(package_manager_executable: nil, "`": "")
    allow(Tap).to receive(:select).and_return([])
  end

  it "generates output" do
    expect(dumper.build_brewfile(
             describe: false, no_restart: false, formulae: true, taps: true, casks: true,
             extension_types: { mas: true, vscode: true, cargo: true, flatpak: false, go: true, uv: true }
           )).to eql("cask \"google-chrome\"\ncask \"java\"\ncask \"homebrew/cask-versions/iterm2-beta\"\n")
  end

  it "determines the brewfile correctly" do
    expect(dumper.brewfile_path).to eql(Pathname.new(Dir.pwd).join("Brewfile"))
  end

  it "preserves the legacy extension dump order" do
    allow(Homebrew::Bundle::Go).to receive(:dump).and_return('go "github.com/charmbracelet/crush"')
    allow(Homebrew::Bundle::Cargo).to receive(:dump).and_return('cargo "ripgrep"')
    allow(Homebrew::Bundle::Uv).to receive(:dump).and_return('uv "mkdocs"')
    allow(Homebrew::Bundle::Flatpak).to receive(:dump).and_return('flatpak "org.gnome.Calculator"')

    expect(dumper.build_brewfile(
             describe: false, no_restart: false, formulae: false, taps: false, casks: false,
             extension_types: { mas: false, vscode: false, cargo: true, flatpak: true, go: true, uv: true }
           )).to eql(<<~BREWFILE)
             go "github.com/charmbracelet/crush"
             cargo "ripgrep"
             uv "mkdocs"
             flatpak "org.gnome.Calculator"
           BREWFILE
  end
end
