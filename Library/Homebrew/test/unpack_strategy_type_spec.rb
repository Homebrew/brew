# typed: strict
# frozen_string_literal: true

require "unpack_strategy"

RSpec.describe UnpackStrategy do
  describe ".from_type" do
    it "deprecates the seven_zip alias" do
      expect { described_class.from_type(:seven_zip) }
        .to raise_error(MethodDeprecatedError, /seven_zip.*p7zip/)
    end

    it "still resolves the seven_zip alias" do
      allow(described_class).to receive(:odeprecated)

      expect(described_class.from_type(:seven_zip)).to eq(UnpackStrategy::P7Zip)
    end

    it "resolves p7zip without a deprecation" do
      expect(described_class.from_type(:p7zip)).to eq(UnpackStrategy::P7Zip)
    end
  end
end
