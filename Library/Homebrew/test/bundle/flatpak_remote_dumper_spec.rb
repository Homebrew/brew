# frozen_string_literal: true

require "bundle"
require "bundle/flatpak_remote_dumper"

RSpec.describe Homebrew::Bundle::FlatpakRemoteDumper do
  subject(:dumper) { described_class }

  context "when there are no remotes" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive_messages(flatpak_installed?: true,
                                                  which_flatpak:      Pathname.new("/usr/bin/flatpak"))
      allow(dumper).to receive(:`).and_return("")
    end

    it "returns empty list" do
      expect(dumper.remote_names).to be_empty
    end

    it "dumps as empty string" do
      expect(dumper.dump).to eql("")
    end
  end

  context "with remotes" do
    before do
      described_class.reset!
      allow(OS).to receive(:mac?).and_return(false)
      allow(Homebrew::Bundle).to receive_messages(flatpak_installed?: true,
                                                  which_flatpak:      Pathname.new("/usr/bin/flatpak"))

      remote_output = <<~OUTPUT
        flathub\thttps://flathub.org/repo/flathub.flatpakrepo
        fedora\thttps://registry.fedoraproject.org/
      OUTPUT

      allow(dumper).to receive(:`).with("/usr/bin/flatpak remote-list --system --columns=name,url 2>/dev/null")
                                  .and_return(remote_output)
    end

    it "returns list of remote names" do
      expect(dumper.remote_names).to contain_exactly("fedora", "flathub")
    end

    it "dumps output" do
      expected_output = <<~EOS.chomp
        flatpak_remote "fedora", "https://registry.fedoraproject.org/"
        flatpak_remote "flathub", "https://flathub.org/repo/flathub.flatpakrepo"
      EOS
      expect(dumper.dump).to eql(expected_output)
    end
  end
end
