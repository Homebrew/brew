# typed: true
# frozen_string_literal: true

require "livecheck/livecheck"

RSpec.describe Homebrew::Livecheck do
  describe ".throttled_version" do
    let(:package) do
      formula do
        T.bind(self, T.class_of(Formula))
        url "https://example.com/package-0.0.1.tar.gz"
      end
    end

    it "selects the highest version allowed by the release interval" do
      matches = %w[0.0.3 0.0.4 0.0.5].to_h { |version| [version, Version.new(version)] }

      expect(described_class.throttled_version(package, matches, Version.new("0.0.5"), throttle_rate: 4))
        .to eq(Version.new("0.0.4"))
    end

    it "returns no version while the time interval has not elapsed" do
      allow(described_class).to receive(:throttle_interval_elapsed?).and_return(false)

      expect(described_class.throttled_version(package, {}, Version.new("0.0.5"), throttle_days: 1)).to be_nil
    end

    it "allows the latest version once the time interval has elapsed" do
      allow(described_class).to receive(:throttle_interval_elapsed?).and_return(true)

      expect(described_class.throttled_version(package, {}, Version.new("0.0.5"), throttle_days: 1))
        .to eq(Version.new("0.0.5"))
    end
  end
end
