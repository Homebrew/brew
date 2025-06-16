# frozen_string_literal: true

require "formula"

RSpec.describe Formula do
  def formula(&block)
    super do
      url "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz"
      instance_eval(&block)
    end
  end

  describe "#brew" do
    it "does not raise an error when the checksum matches" do
      expect do
        f = formula do
          sha256 TESTBALL_SHA256
        end

        f.brew do
          # do nothing
        end
      end.not_to raise_error
    end

    it "raises an error when the checksum doesn't match" do
      expect do
        f = formula do
          sha256 "dcbf5f44743b74add648c7e35e414076632fa3b24463d68d1f6afc5be77024f8"
        end

        f.brew do
          # do nothing
        end
      end.to raise_error(ChecksumMismatchError)
    end
  end
end
