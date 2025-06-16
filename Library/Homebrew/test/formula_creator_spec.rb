# frozen_string_literal: true

require "formula_creator"

RSpec.describe Homebrew::FormulaCreator do
  it "gets name from GitHub archive URL" do
    t = described_class.name_from_url("https://github.com/abitrolly/lapce/archive/v0.3.0.tar.gz")
    expect(t).to eq("lapce")
  end

  it "gets name from gitweb URL" do
    t = described_class.name_from_url("http://www.codesrc.com/gitweb/index.cgi?p=libzipper.git;a=summary")
    expect(t).to eq("libzipper")
  end

  it "gets name from GitHub repo URL" do
    t = described_class.name_from_url("https://github.com/abitrolly/lapce.git")
    expect(t).to eq("lapce")
  end

  it "gets name from GitHub download URL" do
    t = described_class.name_from_url("https://github.com/stella-emu/stella/releases/download/6.7/stella-6.7-src.tar.xz")
    expect(t).to eq("stella")
  end

  it "gets name from generic tarball URL" do
    t = described_class.name_from_url("http://digit-labs.org/files/tools/synscan/releases/synscan-5.02.tar.gz")
    expect(t).to eq("synscan")
  end
end
