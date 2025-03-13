# frozen_string_literal: true

require "spec_helper"
require "cask"

describe Bundle::Dumper do
  subject(:dumper) { described_class }

  before do
    ENV["HOMEBREW_BUNDLE_FILE"] = ""

    allow(Bundle).to receive_messages(cask_installed?: true, mas_installed?: false, whalebrew_installed?: false,
                                      vscode_installed?: false)
    Bundle::BrewDumper.reset!
    Bundle::TapDumper.reset!
    Bundle::CaskDumper.reset!
    Bundle::MacAppStoreDumper.reset!
    Bundle::WhalebrewDumper.reset!
    Bundle::VscodeExtensionDumper.reset!
    Bundle::BrewServices.reset!

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
  end

  it "generates output" do
    expect(dumper.build_brewfile(
             describe: false, no_restart: false, brews: true, taps: true, casks: true, mas: true,
             whalebrew: true, vscode: true
           )).to eql("cask \"google-chrome\"\ncask \"java\"\ncask \"iterm2-beta\"\n")
  end

  it "determines the brewfile correctly" do
    expect(dumper.brewfile_path).to eql(Pathname.new(Dir.pwd).join("Brewfile"))
  end
end
