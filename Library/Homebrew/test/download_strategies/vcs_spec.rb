# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe VCSDownloadStrategy do
  let(:url) { "https://example.com/bar" }
  let(:version) { nil }
  let(:bazaar_strategy) { Class.new(BazaarDownloadStrategy) { public :env }.new(url, "baz", version) }
  let(:cvs_strategy) { Class.new(CVSDownloadStrategy) { public :env }.new(url, "baz", version) }

  describe "#cached_location" do
    it "returns the path of the cached resource" do
      allow_any_instance_of(described_class).to receive(:cache_tag).and_return("foo")
      downloader = Class.new(described_class).new(url, "baz", version)
      expect(downloader.cached_location).to eq(HOMEBREW_CACHE/"baz--foo")
    end
  end

  it "lets Bazaar use the sandbox's private home" do
    allow(Sandbox).to receive(:isolate_operation?).and_return(true)

    expect(bazaar_strategy.env).not_to have_key("BZR_HOME")
  end

  it "grants CVS pserver access only to its password file" do
    strategy = CVSDownloadStrategy.new("cvs://:pserver:anonymous@example.com/repo", "baz", version)
    allow(Sandbox).to receive(:isolate_operation?).and_return(true)
    allow(strategy).to receive(:fetching?).and_return(true)
    ENV["CVS_PASSFILE"] = (mktmpdir/"passwords").to_s

    expect(strategy.command_sandbox&.profile&.rules)
      .to include(have_attributes(allow: true, operation: "file-write*",
                                  filter: have_attributes(path: ENV.fetch("CVS_PASSFILE"), type: :literal)))
  end

  it "uses the CVS password file without requiring USER" do
    ENV.delete("USER")
    ENV["CVS_PASSFILE"] = (mktmpdir/"passwords").to_s

    expect(cvs_strategy.env.fetch("CVS_PASSFILE")).to eq(ENV.fetch("CVS_PASSFILE"))
  end

  it "finds the default CVS password file in the caller's HOME without USER" do
    home = mktmpdir
    ENV["HOME"] = home.to_s
    ENV.delete("USER")
    ENV.delete("CVS_PASSFILE")

    expect(cvs_strategy.env.fetch("CVS_PASSFILE")).to eq("#{home}/.cvspass")
  end

  it "finds the default CVS password file without a passwd entry" do
    home = mktmpdir
    ENV["HOME"] = home.to_s
    ENV.delete("CVS_PASSFILE")
    allow(Etc).to receive(:getpwuid).with(Process.uid).and_raise(ArgumentError)

    expect(cvs_strategy.env.fetch("CVS_PASSFILE")).to eq("#{home}/.cvspass")
  end
end
