# frozen_string_literal: true

require "utils/service"

RSpec.describe Utils::Service do
  describe "::systemd_quote" do
    it "quotes empty strings correctly" do
      expect(described_class.systemd_quote("")).to eq '""'
    end

    it "quotes strings with special characters escaped correctly" do
      expect(described_class.systemd_quote("\a\b\f\n\r\t\v\\"))
        .to eq '"\\a\\b\\f\\n\\r\\t\\v\\\\"'
      expect(described_class.systemd_quote("\"' ")).to eq "\"\\\"' \""
    end

    it "does not escape characters that do not need escaping" do
      expect(described_class.systemd_quote("daemon off;")).to eq '"daemon off;"'
      expect(described_class.systemd_quote("--timeout=3")).to eq '"--timeout=3"'
      expect(described_class.systemd_quote("--answer=foo bar"))
        .to eq '"--answer=foo bar"'
    end
  end
end
