# frozen_string_literal: true

RSpec.describe Cask::Download, :cask do
  describe "#download_name" do
    subject(:download_name) { described_class.new(cask).send(:download_name) }

    context "when the URL basename would create a short symlink name" do
      let(:url) { instance_double(URL, to_s: "https://example.com/app.dmg", specs: {}) }
      let(:cask) do
        instance_double(
          Cask::Cask,
          token:      "example-cask",
          full_token: "example-cask",
          version:    "1.0.0",
          url:,
        )
      end
      let(:download) { described_class.new(cask) }

      before do
        allow(download).to receive(:determine_url).and_return(url)
      end

      it "returns the URL basename" do
        expect(download_name).to eq "app.dmg"
      end
    end

    context "when the URL basename would create a long symlink name" do
      # Simulate the problematic qqmusic case with very long URL and version
      let(:long_url_basename) do
        params = Array.new(50) { |i| "param#{i}=value#{i}" }.join("&")
        "file_redirect.fcg?bid=dldir&file=very-long-filename-with-many-query-parameters&sign=long-signature&#{params}"
      end
      let(:long_version) { "10.7.1,00,1-0cb9ee4c40e7447e2113cfdee2dc11c88487b0e31fe37cfe1c59e12c20956dce-689e9373" }
      let(:url) { instance_double(URL, to_s: "https://example.com/#{long_url_basename}", specs: {}) }
      let(:cask) do
        instance_double(
          Cask::Cask,
          token:      "qqmusic",
          full_token: "qqmusic",
          version:    long_version,
          url:,
        )
      end
      let(:download) { described_class.new(cask) }

      before do
        allow(download).to receive(:determine_url).and_return(url)
      end

      it "returns the cask token when symlink would be too long" do
        expect(download_name).to eq "qqmusic"
      end
    end

    context "when cask is in a third-party tap and symlink would be too long" do
      let(:long_url_basename) do
        params = Array.new(50) { |i| "param#{i}=value#{i}" }.join("&")
        "very-long-filename-with-many-parameters.dmg?#{params}"
      end
      let(:long_version) { "1.0.0-build123456789012345678901234567890" }
      let(:url) { instance_double(URL, to_s: "https://example.com/#{long_url_basename}", specs: {}) }
      let(:cask) do
        instance_double(
          Cask::Cask,
          token:      "example-cask",
          full_token: "homebrew/cask/example-cask",
          version:    long_version,
          url:,
        )
      end
      let(:download) { described_class.new(cask) }

      before do
        allow(download).to receive(:determine_url).and_return(url)
      end

      it "returns the full token with slashes replaced by dashes" do
        expect(download_name).to eq "homebrew--cask--example-cask"
      end
    end

    context "when cask has no version" do
      let(:url) { instance_double(URL, to_s: "https://example.com/app.dmg", specs: {}) }
      let(:cask) do
        instance_double(
          Cask::Cask,
          token:      "example-cask",
          full_token: "example-cask",
          version:    nil,
          url:,
        )
      end
      let(:download) { described_class.new(cask) }

      before do
        allow(download).to receive(:determine_url).and_return(url)
      end

      it "returns the URL basename" do
        expect(download_name).to eq "app.dmg"
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
