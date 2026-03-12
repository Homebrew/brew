# typed: true
# frozen_string_literal: true

require "cask/migrator"

RSpec.describe Cask::Migrator do
  describe ".migrate_if_needed" do
    let(:new_cask) do
      instance_double(
        Cask::Cask,
        old_tokens:         ["old-token"],
        installed_caskfile:,
        token:              new_token,
      )
    end

    context "when the installed token matches the current token" do
      let(:installed_caskfile) { Pathname("/tmp/Casks/docker-desktop.rb") }
      let(:new_token) { "docker-desktop" }

      it "returns without loading or migrating" do
        expect(Cask::Cask).not_to receive(:new)
        expect(described_class).not_to receive(:new)

        described_class.migrate_if_needed(new_cask)
      end
    end

    context "when the installed token differs from the current token" do
      let(:installed_caskfile) { Pathname("/tmp/Casks/old-token.rb") }
      let(:new_token) { "new-token" }

      it "migrates using the installed token from the caskfile path" do
        old_cask = instance_double(Cask::Cask)
        migrator = instance_double(described_class)

        expect(Cask::Cask).to receive(:new).with("old-token").and_return(old_cask)
        expect(described_class).to receive(:new).with(old_cask, new_cask).and_return(migrator)
        expect(migrator).to receive(:migrate).with(dry_run: false)

        described_class.migrate_if_needed(new_cask)
      end
    end
  end
end
