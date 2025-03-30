# frozen_string_literal: true

require "services/commands/cleanup"
require "services/system"
require "services/cli"

RSpec.describe Homebrew::Services::Commands::Cleanup do
  describe "#TRIGGERS" do
    it "contains all restart triggers" do
      expect(described_class::TRIGGERS).to eq(%w[cleanup clean cl rm])
    end
  end

  describe "#run" do
    it "root - prints on empty cleanup" do
      expect(Homebrew::Services::System).to receive(:root?).once.and_return(true)
      expect(Homebrew::Services::Cli).to receive(:kill_orphaned_services).once.and_return([])
      expect(Homebrew::Services::Cli).to receive(:remove_unused_service_files).once.and_return([])

      expect do
        described_class.run
      end.to output("All root services OK, nothing cleaned...\n").to_stdout
    end

    it "user - prints on empty cleanup" do
      expect(Homebrew::Services::System).to receive(:root?).once.and_return(false)
      expect(Homebrew::Services::Cli).to receive(:kill_orphaned_services).once.and_return([])
      expect(Homebrew::Services::Cli).to receive(:remove_unused_service_files).once.and_return([])

      expect do
        described_class.run
      end.to output("All user-space services OK, nothing cleaned...\n").to_stdout
    end

    it "prints nothing on cleanup" do
      expect(Homebrew::Services::System).not_to receive(:root?)
      expect(Homebrew::Services::Cli).to receive(:kill_orphaned_services).once.and_return(["a"])
      expect(Homebrew::Services::Cli).to receive(:remove_unused_service_files).once.and_return(["b"])

      expect do
        described_class.run
      end.not_to output("All user-space services OK, nothing cleaned...\n").to_stdout
    end
  end
end
