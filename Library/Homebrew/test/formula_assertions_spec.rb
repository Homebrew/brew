# frozen_string_literal: true

require "benchmark"
require "formula_assertions"

RSpec.describe Homebrew::Assertions do
  include described_class

  describe "#pty_spawn_output" do
    it "can verify the return code" do
      expect { pty_spawn_output("true", 0) }.not_to raise_error
      expect { pty_spawn_output("true", 1) }.to raise_error(Minitest::Assertion)
      expect { pty_spawn_output("false", 0) }.to raise_error(Minitest::Assertion)
      expect { pty_spawn_output("false", 1) }.not_to raise_error
    end

    it "can adjust the window size" do
      expect(pty_spawn_output("stty size", winsize: [10, 20]).chomp).to eql("10 20")
    end

    it "can terminate long running commands" do
      time = Benchmark.measure do
        expect { pty_spawn_output("sleep 10", timeout: 0.5) }.not_to raise_error
      end
      expect(time.real).to be < 2 # allow some overhead in case of slow tests
    end
  end
end
