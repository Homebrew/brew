# frozen_string_literal: true

require_relative "shared_examples"

describe UnpackStrategy::Zstd do
  let(:path) { TEST_FIXTURE_DIR/"cask/container.tar.zst" }

  it "is correctly detected" do
    # UnpackStrategy.detect(path) for a .tar.XXX file returns either UnpackStrategy::Tar if
    # the host's tar is able to extract that compressed file or UnpackStrategy::XXX otherwise,
    # such as UnpackStrategy::Zstd. On macOS UnpackStrategy.detect("container.tar.zst")
    # returns UnpackStrategy::Zstd, and on ubuntu-22.04 it returns UnpackStrategy::Tar,
    # because the host's version of tar is recent enough and zstd is installed.
    expect(UnpackStrategy.detect(path)).to(be_a(described_class).or(be_a(UnpackStrategy::Tar)))
  end
end
