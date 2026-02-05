# frozen_string_literal: true

require "services/commands/restart"

RSpec.describe Homebrew::Services::Commands::Restart do
  describe "#TRIGGERS" do
    it "contains all restart triggers" do
      expect(described_class::TRIGGERS).to eq(%w[restart relaunch reload r])
    end
  end

  describe "#run" do
    it "fails with empty list" do
      expect do
        described_class.run([], nil, verbose: false)
      end.to raise_error UsageError,
                         "Invalid usage: Formula(e) missing, please provide a formula name or use `--all`."
    end

    it "starts if services are not loaded" do
      expect(Homebrew::Services::Cli).not_to receive(:run)
      expect(Homebrew::Services::Cli).not_to receive(:stop)
      expect(Homebrew::Services::Cli).to receive(:start).once
      service = instance_double(Homebrew::Services::FormulaWrapper, service_name: "name", loaded?: false)
      expect { described_class.run([service], nil, verbose: false) }.not_to raise_error
    end

    it "starts if services are loaded with file" do
      expect(Homebrew::Services::Cli).not_to receive(:run)
      expect(Homebrew::Services::Cli).to receive(:start).once
      expect(Homebrew::Services::Cli).to receive(:stop).once
      service = instance_double(Homebrew::Services::FormulaWrapper, service_name: "name", loaded?: true,
service_file_present?: true)
      expect { described_class.run([service], nil, verbose: false) }.not_to raise_error
    end

    it "runs if services are loaded without file" do
      expect(Homebrew::Services::Cli).not_to receive(:start)
      expect(Homebrew::Services::Cli).to receive(:run).once
      expect(Homebrew::Services::Cli).to receive(:stop).once
      service = instance_double(Homebrew::Services::FormulaWrapper, service_name: "name", loaded?: true,
service_file_present?: false)
      expect { described_class.run([service], nil, verbose: false) }.not_to raise_error
    end
  end
end
