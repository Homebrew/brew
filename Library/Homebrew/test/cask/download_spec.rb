# frozen_string_literal: true

RSpec.describe Cask::Download, :cask do
  describe "#download_name" do
    subject(:download_name) { described_class.new(cask).send(:download_name) }

    let(:download) { described_class.new(cask) }
    let(:token) { "example-cask" }
    let(:full_token) { token }
    let(:url) { instance_double(URL, to_s: url_to_s, specs: {}) }
    let(:url_to_s) { "https://example.com/app.dmg" }
    let(:cask) { instance_double(Cask::Cask, token:, full_token:, version:, url:) }

    before { allow(download).to receive(:determine_url).and_return(url) }

    context "when cask has no version" do
      let(:version) { nil }

      it "returns the URL basename" do
        expect(download_name).to eq "app.dmg"
      end
    end

    context "when the URL basename would create a short symlink name" do
      let(:version) { "1.0.0" }

      it "returns the URL basename" do
        expect(download_name).to eq "app.dmg"
      end
    end

    context "when the URL basename would create a long symlink name" do
      let(:version) do
        "1.2.3,kch23dmbz6whmoogcbss45yi4c2kkq15gmemwys0hgwd3l7cahmx2ciagrlrgppatxaxarzazmdoerzmiisuf7mul4lgcays2dl3nl"
      end
      let(:url_to_s) { "https://example.com/app.dmg?#{Array.new(50) { |i| "param#{i}=value#{i}" }.join("&")}" }

      it "returns the cask token when symlink would be too long" do
        expect(download_name).to eq "example-cask"
      end

      context "when the cask is in a third-party tap" do
        let(:full_token) { "third-party/tap/example-cask" }

        it "returns the full token with slashes replaced by dashes" do
          expect(download_name).to eq "third-party--tap--example-cask"
        end
      end
    end
  end

  describe "#verify_download_integrity" do
    subject(:verification) { described_class.new(cask).verify_download_integrity(downloaded_path) }

    let(:tap) { nil }
    let(:cask) { instance_double(Cask::Cask, token: "cask", sha256: expected_sha256, tap:) }
    let(:cafebabe) { "cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe" }
    let(:deadbeef) { "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef" }
    let(:computed_sha256) { cafebabe }
    let(:downloaded_path) { Pathname.new("cask.zip") }

    before do
      allow(downloaded_path).to receive_messages(file?: true, sha256: computed_sha256)
    end

    context "when the expected checksum is :no_check" do
      let(:expected_sha256) { :no_check }

      it "warns about skipping the check" do
        expect { verification }.to output(/skipping verification/).to_stderr
      end

      context "with an official tap" do
        let(:tap) { CoreCaskTap.instance }

        it "does not warn about skipping the check" do
          expect { verification }.not_to output(/skipping verification/).to_stderr
        end
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
