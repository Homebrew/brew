# frozen_string_literal: true

require "utils/bottles"

RSpec.describe Utils::Bottles::Collector do
  subject(:collector) { described_class.new }

  let(:tahoe) { Utils::Bottles::Tag.from_symbol(:tahoe) }
  let(:sequoia) { Utils::Bottles::Tag.from_symbol(:sequoia) }
  let(:sonoma) { Utils::Bottles::Tag.from_symbol(:sonoma) }

  describe "#specification_for" do
    it "returns passed tags" do
      collector.add(sonoma, checksum: Checksum.new("foo_checksum"), cellar: "foo_cellar")
      collector.add(sequoia, checksum: Checksum.new("bar_checksum"), cellar: "bar_cellar")
      spec = collector.specification_for(sequoia)
      expect(spec).not_to be_nil
      expect(spec.tag).to eq(sequoia)
      expect(spec.checksum).to eq("bar_checksum")
      expect(spec.cellar).to eq("bar_cellar")
    end

    it "returns nil if empty" do
      expect(collector.specification_for(Utils::Bottles::Tag.from_symbol(:foo))).to be_nil
    end

    it "returns nil when there is no match" do
      collector.add(sequoia, checksum: Checksum.new("bar_checksum"), cellar: "bar_cellar")
      expect(collector.specification_for(Utils::Bottles::Tag.from_symbol(:foo))).to be_nil
    end

    it "uses older tags when needed", :needs_macos do
      collector.add(sonoma, checksum: Checksum.new("foo_checksum"), cellar: "foo_cellar")
      expect(collector.send(:find_matching_tag, sonoma)).to eq(sonoma)
      expect(collector.send(:find_matching_tag, sequoia)).to eq(sonoma)
    end

    it "does not use older tags when requested not to", :needs_macos do
      allow(Homebrew::EnvConfig).to receive_messages(developer?: true, skip_or_later_bottles?: true)
      allow(OS::Mac.version).to receive(:prerelease?).and_return(true)
      collector.add(sonoma, checksum: Checksum.new("foo_checksum"), cellar: "foo_cellar")
      expect(collector.send(:find_matching_tag, sonoma)).to eq(sonoma)
      expect(collector.send(:find_matching_tag, sequoia)).to be_nil
    end

    it "ignores HOMEBREW_SKIP_OR_LATER_BOTTLES on release versions", :needs_macos do
      allow(Homebrew::EnvConfig).to receive(:skip_or_later_bottles?).and_return(true)
      allow(OS::Mac.version).to receive(:prerelease?).and_return(false)
      collector.add(sonoma, checksum: Checksum.new("foo_checksum"), cellar: "foo_cellar")
      expect(collector.send(:find_matching_tag, sonoma)).to eq(sonoma)
      expect(collector.send(:find_matching_tag, sequoia)).to eq(sonoma)
    end
  end
end
