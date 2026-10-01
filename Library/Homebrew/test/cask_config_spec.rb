# typed: strict
# frozen_string_literal: true

require "cask/config"

RSpec.describe Cask::Config do
  describe "#languages" do
    it "uses the current operating system language provider" do
      expected_languages = if OS.mac?
        allow(OS::Mac).to receive(:languages).and_return(["en-US"])
        ["en-US"]
      elsif OS.linux?
        allow(OS::Linux).to receive(:languages).and_return(["en-US"])
        ["en-US"]
      else
        []
      end

      expect(described_class.new.languages).to eq(expected_languages)
    end
  end
end
