# frozen_string_literal: true

require "services/service"

RSpec.describe Service::Commands::Restart do
  describe "#TRIGGERS" do
    it "contains all restart triggers" do
      expect(described_class::TRIGGERS).to eq(%w[restart relaunch reload r])
    end
  end

  describe "#run" do
    it "fails with empty list" do
      expect do
        described_class.run([], verbose: false)
      end.to raise_error UsageError,
                         a_string_including("Formula(e) missing, please provide a formula name or use --all")
    end

    it "starts if services are not loaded" do
      expect(Service::ServicesCli).not_to receive(:run)
      expect(Service::ServicesCli).not_to receive(:stop)
      expect(Service::ServicesCli).to receive(:start).once
      service = instance_double(Service::FormulaWrapper, service_name: "name", loaded?: false)
      expect(described_class.run([service], verbose: false)).to be_nil
    end

    it "starts if services are loaded with file" do
      expect(Service::ServicesCli).not_to receive(:run)
      expect(Service::ServicesCli).to receive(:start).once
      expect(Service::ServicesCli).to receive(:stop).once
      service = instance_double(Service::FormulaWrapper, service_name: "name", loaded?: true,
service_file_present?: true)
      expect(described_class.run([service], verbose: false)).to be_nil
    end

    it "runs if services are loaded without file" do
      expect(Service::ServicesCli).not_to receive(:start)
      expect(Service::ServicesCli).to receive(:run).once
      expect(Service::ServicesCli).to receive(:stop).once
      service = instance_double(Service::FormulaWrapper, service_name: "name", loaded?: true,
service_file_present?: false)
      expect(described_class.run([service], verbose: false)).to be_nil
    end
  end
end
