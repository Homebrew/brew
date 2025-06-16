# frozen_string_literal: true

RSpec.describe Cask::CaskLoader::FromPathLoader do
  describe "#load" do
    context "when the file does not contain a cask" do
      let(:path) do
        (mktmpdir/"cask.rb").tap do |path|
          path.write <<~RUBY
            true
          RUBY
        end
      end

      it "raises an error" do
        expect do
          described_class.new(path).load(config: nil)
        end.to raise_error(Cask::CaskUnreadableError, /does not contain a cask/)
      end
    end

    context "when the file calls a non-existent method" do
      let(:path) do
        (mktmpdir/"cask.rb").tap do |path|
          path.write <<~RUBY
            this_method_does_not_exist
          RUBY
        end
      end

      it "raises an error" do
        expect do
          described_class.new(path).load(config: nil)
        end.to raise_error(Cask::CaskUnreadableError, /undefined local variable or method/)
      end
    end

    context "when the file contains an outdated cask" do
      it "raises an error" do
        expect do
          described_class.new(cask_path("invalid/invalid-depends-on-macos-bad-release")).load(config: nil)
        end.to raise_error(Cask::CaskInvalidError,
                           /invalid 'depends_on macos' value: unknown or unsupported macOS version:/)
      end
    end

    context "with a JSON cask file" do
      let(:sourcefile_path) { TEST_FIXTURE_DIR/"cask/everything.json" }

      it "loads a cask with a source file path" do
        cask = described_class.new(sourcefile_path).load(config: nil)
        expect(cask.sourcefile_path).to eq sourcefile_path
      end
    end
  end
end
