# frozen_string_literal: true

require "services/commands/info"

RSpec.describe Homebrew::Services::Commands::Info do
  before do
    allow_any_instance_of(IO).to receive(:tty?).and_return(false)
  end

  describe "#TRIGGERS" do
    it "contains all restart triggers" do
      expect(described_class::TRIGGERS).to eq(%w[info i])
    end
  end

  describe "#run" do
    it "fails with empty list" do
      expect do
        described_class.run([], verbose: false, json: false)
      end.to raise_error UsageError,
                         "Invalid usage: Formula(e) missing, please provide a formula name or use `--all`."
    end

    it "succeeds with items" do
      out = "service ()\nRunning: true\nLoaded: true\nSchedulable: false\n"
      formula_wrapper = instance_double(Homebrew::Services::FormulaWrapper, to_hash: {
        name:        "service",
        user:        "user",
        status:      :started,
        file:        "/dev/null",
        running:     true,
        loaded:      true,
        schedulable: false,
      })
      expect do
        described_class.run([formula_wrapper], verbose: false, json: false)
      end.to output(out).to_stdout
    end

    it "succeeds with items - JSON" do
      formula = {
        name:        "service",
        user:        "user",
        status:      :started,
        file:        "/dev/null",
        running:     true,
        loaded:      true,
        schedulable: false,
      }
      out = "#{JSON.pretty_generate([formula])}\n"
      formula_wrapper = instance_double(Homebrew::Services::FormulaWrapper, to_hash: formula)
      expect do
        described_class.run([formula_wrapper], verbose: false, json: true)
      end.to output(out).to_stdout
    end
  end

  describe "#output" do
    it "returns minimal output" do
      out = "service ()\nRunning: true\n"
      out += "Loaded: true\nSchedulable: false\n"
      formula = {
        name:        "service",
        user:        "user",
        status:      :started,
        file:        "/dev/null",
        running:     true,
        loaded:      true,
        schedulable: false,
      }
      expect(described_class.output(formula, verbose: false)).to eq(out)
    end

    it "returns normal output" do
      out = "service ()\nRunning: true\n"
      out += "Loaded: true\nSchedulable: false\n"
      out += "User: user\nPID: 42\n"
      formula = {
        name:        "service",
        user:        "user",
        status:      :started,
        file:        "/dev/null",
        running:     true,
        loaded:      true,
        schedulable: false,
        pid:         42,
      }
      expect(described_class.output(formula, verbose: false)).to eq(out)
    end

    it "returns verbose output" do
      out = "service ()\nRunning: true\n"
      out += "Loaded: true\nSchedulable: false\n"
      out += "User: user\nPID: 42\nFile: /dev/null true\nRegistered at login: true\nCommand: /bin/command\n"
      out += "Working directory: /working/dir\nRoot directory: /root/dir\nLog: /log/dir\nError log: /log/dir/error\n"
      out += "Interval: 3600s\nCron: 5 * * * *\n"
      formula = {
        name:           "service",
        user:           "user",
        status:         :started,
        file:           "/dev/null",
        registered:     true,
        running:        true,
        loaded:         true,
        schedulable:    false,
        pid:            42,
        command:        "/bin/command",
        working_dir:    "/working/dir",
        root_dir:       "/root/dir",
        log_path:       "/log/dir",
        error_log_path: "/log/dir/error",
        interval:       3600,
        cron:           "5 * * * *",
      }
      expect(described_class.output(formula, verbose: true)).to eq(out)
    end
  end
end
