# frozen_string_literal: true

require "bundle"
require "bundle/flatpak_remote_checker"
require "bundle/flatpak_remote_dumper"
require "bundle/dsl"

RSpec.describe Homebrew::Bundle::Checker::FlatpakRemoteChecker, :needs_linux do
  subject(:checker) { described_class.new }

  let(:entry) do
    Homebrew::Bundle::Dsl::Entry.new(:flatpak_remote, "flathub",
                                     url: "https://flathub.org/repo/flathub.flatpakrepo")
  end

  let(:entries) { [entry] }

  before do
    allow(Homebrew::Bundle::FlatpakRemoteDumper).to receive(:remote_names).and_return([])
  end

  it "finds missing remotes" do
    result = checker.find_actionable(entries)
    expect(result).to contain_exactly("Flatpak Remote flathub needs to be added.")
  end

  it "returns empty when remote exists" do
    allow(Homebrew::Bundle::FlatpakRemoteDumper).to receive(:remote_names).and_return(["flathub"])
    result = checker.find_actionable(entries)
    expect(result).to be_empty
  end
end
