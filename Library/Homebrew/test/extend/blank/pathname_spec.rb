# typed: true
# frozen_string_literal: true

require "extend/blank"

# Modelled on ActiveSupport's `test/core_ext/pathname/blank_test.rb`.
RSpec.describe Pathname do
  let(:blank) { [described_class.new("")] }
  let(:present) { [described_class.new(" "), described_class.new("."), described_class.new("test")] }

  describe "#blank?" do
    it "is blank if and only if the path string is empty" do
      blank.each { |path| expect(path.blank?).to be(true), "#{path.inspect} should be blank" }
      present.each { |path| expect(path.blank?).to be(false), "#{path.inspect} should not be blank" }
    end
  end

  describe "#present?" do
    it "is present if and only if the path string is not empty" do
      blank.each { |path| expect(path.present?).to be(false), "#{path.inspect} should not be present" }
      present.each { |path| expect(path.present?).to be(true), "#{path.inspect} should be present" }
    end
  end

  describe "#presence" do
    it "returns the pathname when present, otherwise nil" do
      blank.each { |path| expect(path.presence).to be_nil }
      present.each { |path| expect(path.presence).to be path }
    end
  end

  describe "filesystem independence" do
    # Before `Pathname#blank?` was redefined it dispatched to the filesystem
    # via `Pathname#empty?`, so the empty path string was present and the
    # existing empty file and directory were blank. A nonexistent path was
    # present under both implementations.
    it "judges by the path string, not filesystem content" do
      expect(described_class.new("").blank?).to be true
      expect(mktmpdir.present?).to be true
      expect((mktmpdir/"nonexistent").present?).to be true
    end

    it "treats an existing empty file as present" do
      file = mktmpdir/"empty-file"
      FileUtils.touch file

      expect(file.present?).to be true
    end
  end
end
