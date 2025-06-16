# frozen_string_literal: true

require "utils/bottles"

RSpec.describe Utils::Bottles::Collector do
  subject(:collector) { described_class.new }

  let(:catalina) { Utils::Bottles::Tag.from_symbol(:catalina) }
  let(:mojave) { Utils::Bottles::Tag.from_symbol(:mojave) }

  describe "#specification_for" do
    it "returns passed tags" do
      collector.add(mojave, checksum: Checksum.new("foo_checksum"), cellar: "foo_cellar")
      collector.add(catalina, checksum: Checksum.new("bar_checksum"), cellar: "bar_cellar")
      spec = collector.specification_for(catalina)
      expect(spec).not_to be_nil
      expect(spec.tag).to eq(catalina)
      expect(spec.checksum).to eq("bar_checksum")
      expect(spec.cellar).to eq("bar_cellar")
    end

    it "returns nil if empty" do
      expect(collector.specification_for(Utils::Bottles::Tag.from_symbol(:foo))).to be_nil
    end

    it "returns nil when there is no match" do
      collector.add(catalina, checksum: Checksum.new("bar_checksum"), cellar: "bar_cellar")
      expect(collector.specification_for(Utils::Bottles::Tag.from_symbol(:foo))).to be_nil
    end

    it "uses older tags when needed", :needs_macos do
      collector.add(mojave, checksum: Checksum.new("foo_checksum"), cellar: "foo_cellar")
      expect(collector.send(:find_matching_tag, mojave)).to eq(mojave)
      expect(collector.send(:find_matching_tag, catalina)).to eq(mojave)
    end

    it "does not use older tags when requested not to", :needs_macos do
      allow(Homebrew::EnvConfig).to receive_messages(developer?: true, skip_or_later_bottles?: true)
      allow(OS::Mac.version).to receive(:prerelease?).and_return(true)
      collector.add(mojave, checksum: Checksum.new("foo_checksum"), cellar: "foo_cellar")
      expect(collector.send(:find_matching_tag, mojave)).to eq(mojave)
      expect(collector.send(:find_matching_tag, catalina)).to be_nil
    end

    it "ignores HOMEBREW_SKIP_OR_LATER_BOTTLES on release versions", :needs_macos do
      allow(Homebrew::EnvConfig).to receive(:skip_or_later_bottles?).and_return(true)
      allow(OS::Mac.version).to receive(:prerelease?).and_return(false)
      collector.add(mojave, checksum: Checksum.new("foo_checksum"), cellar: "foo_cellar")
      expect(collector.send(:find_matching_tag, mojave)).to eq(mojave)
      expect(collector.send(:find_matching_tag, catalina)).to eq(mojave)
    end
  end
end
