# typed: strict
# frozen_string_literal: true

require "sandbox"

RSpec.describe Sandbox do
  it "captures the state of standard input's terminal" do
    PTY.open do |_controller, terminal|
      $stdin.reopen(terminal)

      expect(Class.new(described_class).tty_state).to eq(Utils.popen_read("stty", "-g", in: :in).chomp)
    end
  end

  it "disables terminal echo during passthrough and restores it after an interrupt" do
    sandbox = described_class.new
    allow(sandbox).to receive(:sandbox_command).and_return([])
    allow(sandbox).to receive(:record_sandbox_log)

    PTY.open do |_controller, terminal|
      $stdin.reopen(terminal)
      # IO#echo= also enables ECHONL, which GNU stty raw does not clear.
      Utils.safe_popen_read("stty", "echo", "-echonl", in: :in)
      allow(described_class).to receive(:tty_state).and_return(Utils.popen_read("stty", "-g", in: :in).chomp)
      echo_states = [terminal.echo?]
      allow(Utils).to receive(:safe_fork) do
        echo_states << terminal.echo?
        raise Interrupt
      end

      begin
        sandbox.run("true")
      rescue Interrupt
        echo_states << terminal.echo?
      end

      expect(echo_states).to eq([true, false, true])
    end
  end
end
