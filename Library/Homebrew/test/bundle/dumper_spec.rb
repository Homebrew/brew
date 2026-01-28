# frozen_string_literal: true

require "bundle"
require "bundle/dumper"
require "bundle/formula_dumper"
require "bundle/tap_dumper"
require "bundle/cask_dumper"
require "bundle/mac_app_store_dumper"
require "bundle/vscode_extension_dumper"
require "bundle/brew_services"
require "bundle/go_dumper"
require "bundle/cargo_dumper"
require "cask"

RSpec.describe Homebrew::Bundle::Dumper do
  subject(:dumper) { described_class }

  before do
    ENV["HOMEBREW_BUNDLE_FILE"] = ""

    allow(Homebrew::Bundle).to \
      receive_messages(cask_installed?: true, mas_installed?: false, vscode_installed?: false)
    allow(Homebrew::Bundle).to receive_messages(go_installed?: false, cargo_installed?: false)
    Homebrew::Bundle::FormulaDumper.reset!
    Homebrew::Bundle::TapDumper.reset!
    Homebrew::Bundle::CaskDumper.reset!
    Homebrew::Bundle::MacAppStoreDumper.reset!
    Homebrew::Bundle::VscodeExtensionDumper.reset!
    Homebrew::Bundle::GoDumper.reset!
    Homebrew::Bundle::CargoDumper.reset!
    Homebrew::Bundle::BrewServices.reset!

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
    allow(Homebrew::Bundle::GoDumper).to receive(:`).and_return("")
    allow(Homebrew::Bundle::CargoDumper).to receive(:`).and_return("")
    allow(Tap).to receive(:select).and_return([])
  end

  it "generates output" do
    expect(dumper.build_brewfile(
             describe: false, no_restart: false, formulae: true, taps: true, casks: true, mas: true,
             vscode: true, go: true, cargo: true, flatpak: false
           )).to eql("cask \"google-chrome\"\ncask \"java\"\ncask \"homebrew/cask-versions/iterm2-beta\"\n")
  end

  it "determines the brewfile correctly" do
    expect(dumper.brewfile_path).to eql(Pathname.new(Dir.pwd).join("Brewfile"))
  end
end
