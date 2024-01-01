# frozen_string_literal: true

require "keg_relocate"

describe Keg do
  subject(:keg) { described_class.new(HOMEBREW_CELLAR/"foo/1.0.0") }

  let(:dir) { HOMEBREW_CELLAR/"foo/1.0.0" }
  let(:newdir) { HOMEBREW_CELLAR/"foo" }
  let(:binary_file) { dir/"file.bin" }

  before do
    dir.mkpath
  end

  def setup_binary_file
    binary_file.atomic_write <<~EOS
      \x00#{dir}\x00
    EOS
  end

  describe "#relocate_build_prefix" do
    specify "replace prefix in binary files" do
      setup_binary_file

      keg.relocate_build_prefix(keg, dir, newdir)

      old_prefix_matches = Set.new
      keg.each_unique_file_matching(dir) do |file|
        old_prefix_matches << file
      end

      expect(old_prefix_matches.size).to eq 0

      new_prefix_matches = Set.new
      keg.each_unique_file_matching(newdir) do |file|
        new_prefix_matches << file
      end

      expect(new_prefix_matches.size).to eq 1
    end
  end
end
