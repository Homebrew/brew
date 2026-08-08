# typed: strict
# frozen_string_literal: true

require "utils/service"

RSpec.describe Utils::Service do
  describe "::running?" do
    it "returns false when neither launchctl nor systemctl is available" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      allow(described_class).to receive_messages(launchctl: nil, systemctl?: false)
      expect(described_class.running?(f)).to be false
    end

    it "delegates to System.launchctl_service_running? on macOS" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      allow(described_class).to receive(:launchctl?).and_return(true)
      allow(Homebrew::Services::System).to receive(:launchctl_service_running?)
        .with(f.plist_name).and_return(true)
      expect(described_class.running?(f)).to be true
    end

    it "uses systemctl is-active when systemctl is available" do
      f = formula do
        T.bind(self, T.class_of(Formula))
        url "foo-1.0"
      end
      allow(described_class).to receive_messages(launchctl: nil, systemctl?: true,
                                                 systemctl: Pathname("/bin/systemctl"))
      expect(described_class).to receive(:quiet_system)
        .with(instance_of(Pathname), "is-active", "--quiet", f.service_name)
        .and_return(true)
      expect(described_class.running?(f)).to be true
    end
  end

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
