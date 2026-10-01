# typed: strict
# frozen_string_literal: true

require "mktemp"
require "unpack_strategy"

RSpec.shared_examples "UnpackStrategy::detect" do |deprecated: false|
  it "is correctly detected" do
    if deprecated
      ENV["HOMEBREW_DEVELOPER"] = nil
      Homebrew.raise_deprecation_exceptions = false
    end

    expect(UnpackStrategy.detect(subject)).to be_a described_class
  end
end

RSpec.shared_examples "#extract" do |children: [], verbose: false|
  specify "#extract" do
    Mktemp.new("homebrew-test-unpack").run(chdir: false) do |mktemp|
      unpack_dir = mktemp.tmpdir
      raise "Mktemp did not create a temporary directory" if unpack_dir.nil?

      described_class.new(subject).extract(to: unpack_dir, verbose:)
      expect(unpack_dir.children(false).map(&:to_s)).to match_array children
    end
  end
end
