# frozen_string_literal: true

require "unpack_strategy"

RSpec.shared_examples "UnpackStrategy::detect" do
  it "is correctly detected" do
    expect(UnpackStrategy.detect(path)).to be_a described_class
  end
end

RSpec.shared_examples "#extract" do |children: []|
  specify "#extract" do
    mktmpdir do |unpack_dir|
      described_class.new(path).extract(to: unpack_dir)
      expect(unpack_dir.children(false).map(&:to_s)).to match_array children
    end
  end
end
