# typed: true
# frozen_string_literal: true

require "downloadable"

RSpec.describe Downloadable::VerificationCache do
  subject(:cache) { described_class.new }

  let(:file) { HOMEBREW_CACHE/"downloads/digest-cache-test.tar.gz" }
  let(:checksum) { Checksum.new(Digest::SHA256.hexdigest("contents")) }

  before do
    file.dirname.mkpath
    file.write("contents")
  end

  it "hashes an unchanged file at most once across verifications and digest reads" do
    expect(Digest::SHA256).to receive(:file).once.and_call_original

    cache.verify(file, checksum)
    cache.verify(file, checksum)
    expect(cache.sha256(file)).to eq(checksum.hexdigest)
  end

  it "hashes a file again when its contents change on disk" do
    cache.sha256(file)
    file.write("changed contents")

    expect(cache.sha256(file)).to eq(Digest::SHA256.hexdigest("changed contents"))
  end

  it "hashes a replacement file again despite an identical size and restored modification time" do
    modification_time = Time.utc(2026, 1, 1)
    File.utime(modification_time, modification_time, file)
    cache.sha256(file)
    replacement = file.dirname/"replacement.tar.gz"
    replacement.write("CONTENTS")
    File.utime(modification_time, modification_time, replacement)
    FileUtils.mv(replacement, file)

    expect(cache.sha256(file)).to eq(Digest::SHA256.hexdigest("CONTENTS"))
  end

  it "raises for a checksum mismatch without rehashing the unchanged file" do
    bad_checksum = Checksum.new("bad0" * 16)
    expect(Digest::SHA256).to receive(:file).once.and_call_original

    2.times do
      expect { cache.verify(file, bad_checksum) }.to raise_error(ChecksumMismatchError) do |error|
        expect(error.actual).to eq(checksum)
      end
    end
  end

  it "reuses the digest of a file already hashed at its real path when verifying through a symlink" do
    symlink = file.dirname/"digest-cache-symlink.tar.gz"
    FileUtils.rm_f(symlink)
    FileUtils.ln_s(file, symlink)
    expect(Digest::SHA256).to receive(:file).once.and_call_original

    cache.verify(file, checksum)
    cache.verify(symlink, checksum)
  end

  it "hashes a file again after its remembered digest is invalidated" do
    expect(Digest::SHA256).to receive(:file).twice.and_call_original

    cache.sha256(file)
    cache.invalidate!(file)
    expect(cache.sha256(file)).to eq(checksum.hexdigest)
  end

  describe "::check_repeated_hashing" do
    before do
      ENV["HOMEBREW_CHECK_REPEATED_HASHING"] = "1"
    end

    it "raises when an unchanged file is rehashed without the cache being involved" do
      file.sha256

      expect { file.sha256 }.to raise_error(Downloadable::VerificationCache::RepeatedHashingError)
    end

    it "raises when a file already hashed through the cache is rehashed directly" do
      cache.sha256(file)

      expect { file.sha256 }.to raise_error(Downloadable::VerificationCache::RepeatedHashingError)
    end

    it "allows repeated digest reads through the cache" do
      cache.sha256(file)

      expect(cache.sha256(file)).to eq(checksum.hexdigest)
    end
  end
end
