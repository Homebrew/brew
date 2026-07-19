# typed: true
# frozen_string_literal: true

require "services/system"
require "services/system/systemctl"
require "test/support/helper/services"

RSpec.describe Homebrew::Services::System::Systemctl do
  include Test::Helper::Services

  let(:bindir) { mktmpdir }

  describe ".scope" do
    it "outputs systemctl scope for user" do
      allow(Homebrew::Services::System).to receive(:root?).and_return(false)
      expect(described_class.scope).to eq("--user")
    end

    it "outputs systemctl scope for root" do
      allow(Homebrew::Services::System).to receive(:root?).and_return(true)
      expect(described_class.scope).to eq("--system")
    end
  end

  describe ".executable" do
    it "outputs systemctl command location" do
      systemctl = bindir/"systemctl"
      systemctl.write <<~SH
        #!/bin/sh
        exit 0
      SH
      systemctl.chmod 0755
      reset_services_memoization!

      with_env(PATH: bindir.to_s) do
        expect(described_class.executable).to eq(systemctl)
      end
    end
  end
end
