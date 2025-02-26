# frozen_string_literal: true

require "services/service"

# needs for tty color tests
module Tty
  def self.green
    "<GREEN>"
  end

  def self.yellow
    "<YELLOW>"
  end

  def self.red
    "<RED>"
  end

  def self.default
    "<DEFAULT>"
  end

  def self.bold
    "<BOLD>"
  end

  def self.reset
    "<RESET>"
  end
end

RSpec.describe Service::Commands::List do
  describe "#TRIGGERS" do
    it "contains all restart triggers" do
      expect(described_class::TRIGGERS).to eq([nil, "list", "ls"])
    end
  end

  describe "#run" do
    it "fails with empty list" do
      allow_any_instance_of(IO).to receive(:tty?).and_return(true)
      expect(Service::Formulae).to receive(:services_list).and_return([])
      expect do
        described_class.run
      end.to output(a_string_including("No services available to control with `brew services`")).to_stderr
    end

    it "succeeds with list" do
      out = "<BOLD>Name    Status       User File<RESET>\nservice <GREEN>started<RESET> user /dev/null\n"
      formula = instance_double(
        Service::FormulaWrapper,
        name:          "service",
        owner:         "user",
        status_symbol: :started,
        service_file:  +File::NULL,
        loaded?:       true,
      )
      expect(Service::Formulae).to receive(:services_list).and_return([formula])
      expect do
        described_class.run
      end.to output(out).to_stdout
    end

    it "succeeds with list - JSON" do
      formula = {
        name:        "service",
        user:        "user",
        status:      :started,
        file:        "/dev/null",
        running:     true,
        loaded:      true,
        schedulable: false,
      }

      filtered_formula = formula.slice(*described_class::JSON_FIELDS)
      expected_output = "#{JSON.pretty_generate([filtered_formula])}\n"

      expect(Service::Formulae).to receive(:services_list).and_return([formula])
      expect do
        described_class.run(json: true)
      end.to output(expected_output).to_stdout
    end
  end

  describe "#print_table" do
    it "prints all standard values" do
      formula = { name: "a", user: "u", file: Pathname.new("/tmp/file.file"), status: :stopped }
      expect do
        described_class.print_table([formula])
      end.to output("<BOLD>Name Status         User File<RESET>\na    <DEFAULT>stopped<RESET> u    \n").to_stdout
    end

    it "prints without user or file data" do
      formula = { name: "a", user: nil, file: nil, status: :started, loaded: true }
      expect do
        described_class.print_table([formula])
      end.to output("<BOLD>Name Status       User File<RESET>\na    <GREEN>started<RESET>      \n").to_stdout
    end

    it "prints shortened home directory" do
      ENV["HOME"] = "/tmp"
      formula = { name: "a", user: "u", file: Pathname.new("/tmp/file.file"), status: :started, loaded: true }
      expected_output = "<BOLD>Name Status       User File<RESET>\na    <GREEN>started<RESET> u    ~/file.file\n"
      expect do
        described_class.print_table([formula])
      end.to output(expected_output).to_stdout
    end

    it "prints an error code" do
      file = Pathname.new("/tmp/file.file")
      formula = { name: "a", user: "u", file:, status: :error, exit_code: 256, loaded: true }
      expected_output = "<BOLD>Name Status        User File<RESET>\na    <RED>error  <RESET>256 u    /tmp/file.file\n"
      expect do
        described_class.print_table([formula])
      end.to output(expected_output).to_stdout
    end
  end

  describe "#print_json" do
    it "prints all standard values" do
      formula = { name: "a", status: :stopped, user: "u", file: Pathname.new("/tmp/file.file") }
      expected_output = "#{JSON.pretty_generate([formula])}\n"
      expect do
        described_class.print_json([formula])
      end.to output(expected_output).to_stdout
    end

    it "prints without user or file data" do
      formula = { name: "a", user: nil, file: nil, status: :started, loaded: true }
      filtered_formula = formula.slice(*described_class::JSON_FIELDS)
      expected_output = "#{JSON.pretty_generate([filtered_formula])}\n"
      expect do
        described_class.print_json([formula])
      end.to output(expected_output).to_stdout
    end

    it "includes an exit code" do
      file = Pathname.new("/tmp/file.file")
      formula = { name: "a", user: "u", file:, status: :error, exit_code: 256, loaded: true }
      filtered_formula = formula.slice(*described_class::JSON_FIELDS)
      expected_output = "#{JSON.pretty_generate([filtered_formula])}\n"
      expect do
        described_class.print_json([formula])
      end.to output(expected_output).to_stdout
    end
  end

  describe "#get_status_string" do
    it "returns started" do
      expect(described_class.get_status_string(:started)).to eq("<GREEN>started<RESET>")
    end

    it "returns stopped" do
      expect(described_class.get_status_string(:stopped)).to eq("<DEFAULT>stopped<RESET>")
    end

    it "returns error" do
      expect(described_class.get_status_string(:error)).to eq("<RED>error  <RESET>")
    end

    it "returns unknown" do
      expect(described_class.get_status_string(:unknown)).to eq("<YELLOW>unknown<RESET>")
    end

    it "returns other" do
      expect(described_class.get_status_string(:other)).to eq("<YELLOW>other<RESET>")
    end
  end
end
