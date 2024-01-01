# frozen_string_literal: true

require "compilers"

describe CompilerFailure do
  alias_matcher :fail_with, :be_fails_with

  describe "::create" do
    it "creates a failure when given a symbol" do
      failure = described_class.create(:clang)
      expect(failure).to fail_with(
        instance_double(CompilerSelector::Compiler, "Compiler", type: :clang, name: :clang, version: 600),
      )
    end

    it "can be given a build number in a block" do
      failure = described_class.create(:clang) { build 700 }
      expect(failure).to fail_with(
        instance_double(CompilerSelector::Compiler, "Compiler", type: :clang, name: :clang, version: 700),
      )
    end

    it "can be given an empty block" do
      failure = described_class.create(:clang) do
        # do nothing
      end
      expect(failure).to fail_with(
        instance_double(CompilerSelector::Compiler, "Compiler", type: :clang, name: :clang, version: 600),
      )
    end

    it "creates a failure when given a hash" do
      failure = described_class.create(gcc: "7")
      expect(failure).to fail_with(
        instance_double(CompilerSelector::Compiler, "Compiler", type: :gcc, name: "gcc-7", version: Version.new("7")),
      )
      expect(failure).to fail_with(
        instance_double(
          CompilerSelector::Compiler, "Compiler", type: :gcc, name: "gcc-7", version: Version.new("7.1")
        ),
      )
      expect(failure).not_to fail_with(
        instance_double(
          CompilerSelector::Compiler, "Compiler", type: :gcc, name: "gcc-6", version: Version.new("6.0")
        ),
      )
    end

    it "creates a failure when given a hash and a block with aversion" do
      failure = described_class.create(gcc: "7") { version "7.1" }
      expect(failure).to fail_with(
        instance_double(CompilerSelector::Compiler, "Compiler", type: :gcc, name: "gcc-7", version: Version.new("7")),
      )
      expect(failure).to fail_with(
        instance_double(
          CompilerSelector::Compiler, "Compiler", type: :gcc, name: "gcc-7", version: Version.new("7.1")
        ),
      )
      expect(failure).not_to fail_with(
        instance_double(
          CompilerSelector::Compiler, "Compiler", type: :gcc, name: "gcc-7", version: Version.new("7.2")
        ),
      )
    end
  end
end
