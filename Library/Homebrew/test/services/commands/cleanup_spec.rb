# frozen_string_literal: true

require "services/service"

RSpec.describe Service::Commands::Cleanup do
  describe "#TRIGGERS" do
    it "contains all restart triggers" do
      expect(described_class::TRIGGERS).to eq(%w[cleanup clean cl rm])
    end
  end

  describe "#run" do
    it "root - prints on empty cleanup" do
      expect(Service::System).to receive(:root?).once.and_return(true)
      expect(Service::ServicesCli).to receive(:kill_orphaned_services).once.and_return([])
      expect(Service::ServicesCli).to receive(:remove_unused_service_files).once.and_return([])

      expect do
        described_class.run
      end.to output("All root services OK, nothing cleaned...\n").to_stdout
    end

    it "user - prints on empty cleanup" do
      expect(Service::System).to receive(:root?).once.and_return(false)
      expect(Service::ServicesCli).to receive(:kill_orphaned_services).once.and_return([])
      expect(Service::ServicesCli).to receive(:remove_unused_service_files).once.and_return([])

      expect do
        described_class.run
      end.to output("All user-space services OK, nothing cleaned...\n").to_stdout
    end

    it "prints nothing on cleanup" do
      expect(Service::System).not_to receive(:root?)
      expect(Service::ServicesCli).to receive(:kill_orphaned_services).once.and_return(["a"])
      expect(Service::ServicesCli).to receive(:remove_unused_service_files).once.and_return(["b"])

      expect do
        described_class.run
      end.not_to output("All user-space services OK, nothing cleaned...\n").to_stdout
    end
  end
end
