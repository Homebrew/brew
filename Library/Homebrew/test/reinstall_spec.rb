# typed: strict
# frozen_string_literal: true

require "reinstall"

RSpec.describe Homebrew::Reinstall do
  describe ".backup" do
    it "removes a stale reinstall backup keg" do
      keg_path = HOMEBREW_CELLAR/"testball/0.1"
      (keg_path/"bin").mkpath
      keg = Keg.new(keg_path)
      backup = Pathname.new("#{keg}.reinstall")

      (keg_path/"bin/test").write("current")
      (backup/"bin").mkpath
      (backup/"bin/test").write("stale")

      described_class.send(:backup, keg)

      expect(keg_path).not_to exist
      expect(backup/"bin/test").to exist
      expect((backup/"bin/test").read).to eq("current")
    end
  end
end
