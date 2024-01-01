# frozen_string_literal: true

module Cask
  describe Download, :cask do
    describe "#verify_download_integrity" do
      subject(:verification) { described_class.new(cask).verify_download_integrity(downloaded_path) }

      let(:cask) { instance_double(Cask, token: "cask", sha256: expected_sha256) }
      let(:cafebabe) { "cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe" }
      let(:deadbeef) { "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" }
      let(:computed_sha256) { cafebabe }
      let(:downloaded_path) { Pathname.new("cask.zip") }

      before do
        allow(downloaded_path).to receive_messages(file?: true, sha256: computed_sha256)
      end

      context "when the expected checksum is :no_check" do
        let(:expected_sha256) { :no_check }

        it "skips the check" do
          expect { verification }.to output(/skipping verification/).to_stderr
        end
      end

      context "when expected and computed checksums match" do
        let(:expected_sha256) { Checksum.new(cafebabe) }

        it "does not raise an error" do
          expect { verification }.not_to raise_error
        end
      end

      context "when the expected checksum is nil" do
        let(:expected_sha256) { nil }

        it "outputs an error" do
          expect { verification }.to output(/sha256 "#{computed_sha256}"/).to_stderr
        end
      end

      context "when the expected checksum is empty" do
        let(:expected_sha256) { Checksum.new("") }

        it "outputs an error" do
          expect { verification }.to output(/sha256 "#{computed_sha256}"/).to_stderr
        end
      end

      context "when expected and computed checksums do not match" do
        let(:expected_sha256) { Checksum.new(deadbeef) }

        it "raises an error" do
          expect { verification }.to raise_error ChecksumMismatchError
        end
      end
    end
  end
end
