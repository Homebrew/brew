# typed: false
# frozen_string_literal: true

require "mktemp"
require "unpack_strategy"

RSpec.shared_examples "UnpackStrategy::detect" do
  it "is correctly detected" do
    expect(UnpackStrategy.detect(path)).to be_a described_class
  end
end

RSpec.shared_examples "#extract" do |children: [], verbose: false|
  specify "#extract" do
    Mktemp.new("homebrew-test-unpack").run(chdir: false) do |mktemp|
      unpack_dir = T.must(mktemp.tmpdir)
      described_class.new(path).extract(to: unpack_dir, verbose:)
      expect(unpack_dir.children(false).map(&:to_s)).to match_array children
    end
  end
end
